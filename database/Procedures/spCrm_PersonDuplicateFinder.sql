SET STATISTICS TIME OFF
SET NOCOUNT ON
GO

/*
<doc>
	<summary>
 		This stored procedure detects potential duplicate person records and stores the results in [PersonDuplicate]
	</summary>
	
	<remarks>	
		Uses the following constants:
			##TODO##
	</remarks>
	<code>
		EXEC [dbo].[spCrm_PersonDuplicateFinder]
	</code>
</doc>
*/
ALTER PROCEDURE [dbo].[spCrm_PersonDuplicateFinder]
AS
BEGIN
    BEGIN TRANSACTION

    -- prevent stored proc from running simultaneously since we are using #temp tables
    EXEC sp_getapplock 'spCrm_PersonDuplicateFinder'
        ,'Exclusive'
        ,'Transaction'
        ,0

       -- don't compare people that are both inactive...

    DECLARE @compareByEmail BIT = 1
        ,@compareByName BIT = 1
        ,@compareByPhone BIT = 1
        ,@compareByAddress BIT = 1
        ,@compareByBirthDate BIT = 1
        ,@compareByGender BIT = 1
        ,@compareByCampus BIT = 1
        ,@compareByMaritalStatus BIT = 1
    -- Scores
    -- ones marked ** only added to score if already a potential match
    DECLARE @cScoreWeightEmail INT = 4
        ,@cScoreWeightName INT = 3
        ,@cScoreWeightPhoneNumber INT = 2
        ,@cScoreWeightAddress INT = 2
        ,@cScoreWeightBirthdate INT = 3 -- **
        ,@cScoreWeightGender INT = 3 -- **
        ,@cScoreWeightCampus INT = 1 -- **
        ,@cScoreWeightMaritalStatus INT = 1 -- **
        ,@cScoreFullFirstName INT = 3 -- ** subtract scorewieghtname???
        ,@cScoreFullLastName INT = 3 -- **
        ,@cRecordStatusActive INT = 42
        -- Guids that this proc uses
    DECLARE @cGROUPTYPE_FAMILY_GUID UNIQUEIDENTIFIER = '790E3215-3B10-442B-AF69-616C0DCB998E'
        ,@cLOCATION_TYPE_HOME_GUID UNIQUEIDENTIFIER = '8C52E53C-2A66-435A-AE6E-5EE307D9A0DC'
        ,@cHOME_PHONENUMBER_DEFINEDVALUE_GUID UNIQUEIDENTIFIER = '407E7E45-7B2E-4FCD-9605-ECB1339F2453'
        ,@cCELL_PHONENUMBER_DEFINEDVALUE_GUID UNIQUEIDENTIFIER = 'AA8732FB-2CEA-4C76-8D6D-6AAA2C6A4303'
    -- other
    DECLARE @processDateTime DATETIME = SYSDATETIME()
        ,@cHOME_PHONENUMBER_DEFINEDVALUE_ID INT = (
            SELECT TOP 1 [Id]
            FROM [DefinedValue]
            WHERE [Guid] = @cHOME_PHONENUMBER_DEFINEDVALUE_GUID
            )
        ,@cCELL_PHONENUMBER_DEFINEDVALUE_ID INT = (
            SELECT TOP 1 [Id]
            FROM [DefinedValue]
            WHERE [Guid] = @cCELL_PHONENUMBER_DEFINEDVALUE_GUID
            )
        ,@cGROUPTYPE_FAMILY_ID INT = (
            SELECT TOP 1 [Id]
            FROM GroupType
            WHERE [Guid] = @cGROUPTYPE_FAMILY_GUID
            )
        ,@cLOCATION_TYPE_HOME_ID INT = (
            SELECT TOP 1 [Id]
            FROM DefinedValue
            WHERE [Guid] = @cLOCATION_TYPE_HOME_GUID
            )

    /*
    Populate Temporary Tables for each match criteria
    */
    -- Find Duplicates by looking at people with the exact same email address
    CREATE TABLE #PersonDuplicateByEmailTable (
        Id INT NOT NULL IDENTITY(1, 1)
        ,Email NVARCHAR(75) NOT NULL
        ,PersonAliasId INT NOT NULL
        ,CONSTRAINT [pk_PersonDuplicateByEmailTable] PRIMARY KEY CLUSTERED (Id)
        );

    INSERT INTO #PersonDuplicateByEmailTable (
        Email
        ,PersonAliasId
        )
    SELECT [e].[Email] [Email]
        ,[pa].[Id] [PersonAliasId]
    FROM (
        SELECT [a].[Email]
        FROM (
            SELECT [Email]
                ,COUNT(*) [EmailCount]
            FROM [Person] [p]
            WHERE isnull([Email], '') != ''
            GROUP BY [Email]
            ) [a]
        WHERE [a].[EmailCount] > 1
        ) [e]
    JOIN [Person] [p] ON [p].[Email] = [e].[Email]
    JOIN [PersonAlias] [pa] ON [pa].[PersonId] = [p].[Id]
    WHERE [pa].[AliasPersonId] = [pa].[PersonId] -- limit to only the primary alias
        AND @compareByEmail = 1

    -- Find Duplicates by looking at people with the exact same lastname and same first 2 chars of First/Nick name
    CREATE TABLE #PersonDuplicateByNameTable (
        Id INT NOT NULL IDENTITY(1, 1)
        ,LastName NVARCHAR(50) NOT NULL
        ,First2 NVARCHAR(50) NOT NULL -- intentionally 50 vs 2 for performance reasons (sql server spends time on the length constraint if it's shorter than the source column)
        ,PersonAliasId INT NOT NULL
        ,CONSTRAINT [pk_PersonDuplicateByNameTable] PRIMARY KEY CLUSTERED (Id)
        );

    INSERT INTO #PersonDuplicateByNameTable (
        LastName
        ,First2
        ,PersonAliasId
        )
    SELECT [e].[LastName]
        ,[e].[First2]
        ,[pa].[Id] [PersonAliasId]
    FROM (
        SELECT [a].[First2]
            ,[a].[LastName]
        FROM (
            SELECT SUBSTRING([FirstName], 1, 2) [First2]
                ,[LastName]
                ,COUNT(*) [MatchCount]
            FROM [Person] [p]
            WHERE isnull([LastName], '') != ''
                AND [FirstName] IS NOT NULL
                AND LEN([FirstName]) >= 2
            GROUP BY [LastName]
                ,SUBSTRING([FirstName], 1, 2)
            ) [a]
        WHERE [a].[MatchCount] > 1
        ) [e]
    JOIN [Person] [p] ON [p].[LastName] = [e].[LastName]
        AND [p].[FirstName] LIKE (e.First2 + '%')
    JOIN [PersonAlias] [pa] ON [pa].[PersonId] = [p].[Id]
    WHERE [pa].[AliasPersonId] = [pa].[PersonId] -- limit to only the primary alias
        AND @compareByName = 1

    -- Find Duplicates by looking at people with the exact same phone number
    CREATE TABLE #PersonDuplicateByPhoneTable (
        Id INT NOT NULL IDENTITY(1, 1)
        ,Number NVARCHAR(20) NOT NULL
        ,Extension NVARCHAR(20) NOT NULL
        ,CountryCode NVARCHAR(3) NOT NULL
        ,NumberTypeValueId INT NOT NULL
        ,Gender INT NOT NULL
        ,PersonAliasId INT NOT NULL
        ,CONSTRAINT [pk_PersonDuplicateByPhoneTable] PRIMARY KEY CLUSTERED (Id)
        );

    INSERT INTO #PersonDuplicateByPhoneTable (
        Number
        ,Extension
        ,CountryCode
        ,NumberTypeValueId
        ,Gender
        ,PersonAliasId
        )
    SELECT [m].[Number]
        ,isnull([m].[Extension], '')
        ,isnull([m].[CountryCode], '')
        ,[m].[NumberTypeValueId]
        ,[p].[Gender]
        ,[pa].[Id] [PersonAliasId]
    FROM (
        SELECT DISTINCT [Number]
            ,[Extension]
            ,[CountryCode]
            ,[NumberTypeValueId]
            ,[Gender]
        FROM (
            SELECT [pn].[Number]
                ,[pn].[Extension]
                ,[pn].[CountryCode]
                ,[pn].[NumberTypeValueId]
                ,[p].[Gender]
                ,COUNT(*) [MatchCount]
            FROM [PhoneNumber] [pn]
            JOIN [Person] [p] ON [p].[Id] = [pn].[PersonId]
            WHERE ISNUMERIC([pn].[Number]) = 1
                AND [pn].[NumberTypeValueId] IN (
                    @cHOME_PHONENUMBER_DEFINEDVALUE_ID
                    ,@cCELL_PHONENUMBER_DEFINEDVALUE_ID
                    )
            GROUP BY [pn].[Number]
                ,[pn].[Extension]
                ,[pn].[CountryCode]
                ,[pn].[NumberTypeValueId]
                ,[p].[Gender]
            ) [a]
        WHERE [a].[MatchCount] > 1
        ) [m]
    JOIN [PhoneNumber] [pn] ON [pn].[Number] = [m].[Number]
        AND ISNULL([pn].[Extension], '') = ISNULL([m].[Extension], '')
        AND ISNULL([pn].[CountryCode], '') = ISNULL([m].[CountryCode], '')
        AND [pn].[NumberTypeValueId] = [m].[NumberTypeValueId]
    JOIN [PersonAlias] [pa] ON [pa].[PersonId] = [pn].[PersonId]
    JOIN [Person] [p] ON [p].[Id] = [pa].[PersonId]
    WHERE [m].[Gender] = [p].[Gender] -- only consider it a potential duplicate person if the gender and the phone number are the same (to reduce false matches)
        AND [pa].[AliasPersonId] = [pa].[PersonId] -- limit to only the primary alias
        AND @compareByPhone = 1

    -- Find Duplicates by looking at people with the exact same address (Location)
    CREATE TABLE #PersonDuplicateByAddressTable (
        Id INT NOT NULL IDENTITY(1, 1)
        ,LocationId INT NOT NULL
        ,Gender INT NOT NULL
        ,GroupRoleId INT NOT NULL
        ,PersonAliasId INT NOT NULL
        ,CONSTRAINT [pk_PersonDuplicateByAddressTable] PRIMARY KEY CLUSTERED (Id)
        );

    INSERT INTO #PersonDuplicateByAddressTable (
        LocationId
        ,Gender
        ,GroupRoleId
        ,PersonAliasId
        )
    -- from the locations that have multiple potential duplicate persons, select the person records (along with gender and family role) that are associated with that location
    -- in case the person has multiple home addresses, get the first one with preference given to MapLocation=true
    SELECT CASE 
            WHEN a.MaxMappedLocationId > 0
                THEN a.MaxMappedLocationId
            ELSE a.MaxNotMappedLocationId
            END [LocationId]
        ,[Gender]
        ,[GroupRoleId]
        ,[PersonAliasId]
    FROM (
        SELECT max(CASE 
                    WHEN [IsMappedLocation] = 1
                        THEN [LocationId]
                    ELSE 0
                    END) [MaxMappedLocationId]
            ,max(CASE 
                    WHEN [IsMappedLocation] = 0
                        THEN [LocationId]
                    ELSE 0
                    END) [MaxNotMappedLocationId]
            ,[Gender]
            ,[GroupRoleId]
            ,[PersonAliasId]
        FROM (
            SELECT [m].[LocationId]
                ,[gl].[IsMappedLocation]
                ,[m].[Gender]
                ,[m].[GroupRoleId]
                ,[pa].[Id] [PersonAliasId]
            FROM (
                SELECT [LocationId]
                    ,[Gender]
                    ,[GroupRoleId]
                    ,[MatchCount]
                FROM (
                    -- consider it a potential duplicate person if multiple people have the same address (LocationId), Gender and GroupRole (adult, child)
                    SELECT [gl].[LocationId]
                        ,[gm].[GroupRoleId]
                        ,[p].[Gender]
                        ,COUNT(*) [MatchCount]
                    FROM [Person] [p]
                    JOIN [GroupMember] [gm] ON [gm].[PersonId] = [p].[Id]
                    JOIN [Group] [g] ON [gm].[GroupId] = [g].[Id]
                    JOIN [GroupLocation] [gl] ON [gl].[GroupId] = [g].[id]
                    JOIN [Location] [l] ON [l].[Id] = [gl].[LocationId]
                        AND [g].[GroupTypeId] = @cGROUPTYPE_FAMILY_ID
                    WHERE [gl].[GroupLocationTypeValueId] = @cLOCATION_TYPE_HOME_ID
                    GROUP BY [gl].[LocationID]
                        ,[p].[Gender]
                        ,[gm].[GroupRoleId]
                    ) [a]
                WHERE [MatchCount] > 1
                ) [m]
            JOIN [GroupLocation] [gl] ON [gl].[LocationId] = [m].[LocationId]
            JOIN [Group] [g] ON [g].[Id] = [gl].[GroupId]
            JOIN [GroupMember] [gm] ON [gm].[GroupId] = [g].[Id]
            JOIN [PersonAlias] [pa] ON [gm].[PersonId] = [pa].[PersonId]
            JOIN [Person] [p] ON [p].[Id] = [pa].[PersonId]
            WHERE [m].[Gender] = [p].[Gender]
                AND [m].[GroupRoleId] = [gm].[GroupRoleId] -- only consider it a potential duplicate person if the gender,role and location are the same (to reduce false matches due to married couples)
                AND [pa].[AliasPersonId] = [pa].[PersonId] -- limit to only the primary alias
                AND @compareByAddress = 1
            ) [a]
        GROUP BY [PersonAliasId]
            ,[Gender]
            ,[GroupRoleId]
        ) a

    /* 
    Reset Scores for everybody. (We want to preserve each record's [IsConfirmedAsNotDuplicate] value)
    */
    UPDATE [PersonDuplicate]
    SET [Score] = 0
        ,[ScoreDetail] = '';

    /*
    Merge Results of Matches into PersonDuplicate Table
    */
    -- Update PersonDuplicate table with results of email match
    MERGE [PersonDuplicate] AS TARGET
    USING (
        SELECT [e1].[PersonAliasId] [PersonAliasId]
            ,[e2].[PersonAliasId] [DuplicatePersonAliasId]
            ,[e1].[Email] [Email]
        FROM #PersonDuplicateByEmailTable [e1]
        JOIN #PersonDuplicateByEmailTable [e2] ON [e1].[email] = [e2].[email]
            AND [e1].[Id] != [e2].[Id]
            AND [e1].[PersonAliasId] > [e2].[PersonAliasId] -- we only need the matched pair in there once (don't need both PersonA == PersonB and PersonB == PersonA)
        ) AS source(PersonAliasId, DuplicatePersonAliasId, Email)
        ON (target.PersonAliasId = source.PersonAliasId)
            AND (target.DuplicatePersonAliasId = source.DuplicatePersonAliasId)
    WHEN MATCHED
        THEN
            UPDATE
            SET [Score] = [Score] + @cScoreWeightEmail
                ,[ScoreDetail] += '|Email'
                ,[ModifiedDateTime] = @processDateTime
    WHEN NOT MATCHED
        THEN
            INSERT (
                PersonAliasId
                ,DuplicatePersonAliasId
                ,Score
                ,ScoreDetail
                ,IsConfirmedAsNotDuplicate
                ,ModifiedDateTime
                ,CreatedDateTime
                ,[Guid]
                )
            VALUES (
                source.PersonAliasId
                ,source.DuplicatePersonAliasId
                ,@cScoreWeightEmail
                ,'|Email'
                ,0
                ,@processDateTime
                ,@processDateTime
                ,NEWID()
                );

    -- Update PersonDuplicate table with results of name match
    MERGE [PersonDuplicate] AS TARGET
    USING (
        SELECT [e1].[PersonAliasId] [PersonAliasId]
            ,[e2].[PersonAliasId] [DuplicatePersonAliasId]
            ,[e1].[First2] [First2]
            ,[e1].[LastName] [LastName]
        FROM #PersonDuplicateByNameTable [e1]
        JOIN #PersonDuplicateByNameTable [e2] ON [e1].[First2] = [e2].[First2]
            AND [e1].[LastName] = [e2].[LastName]
            AND [e1].[Id] != [e2].[Id]
            AND [e1].[PersonAliasId] > [e2].[PersonAliasId] -- we only need the matched pair in there once (don't need both PersonA == PersonB and PersonB == PersonA)
        ) AS source(PersonAliasId, DuplicatePersonAliasId, LastName, First2)
        ON (target.PersonAliasId = source.PersonAliasId)
            AND (target.DuplicatePersonAliasId = source.DuplicatePersonAliasId)
    WHEN MATCHED
        THEN
            UPDATE
            SET [Score] = [Score] + @cScoreWeightName
                ,[ScoreDetail] += '|Name'
                ,[ModifiedDateTime] = @processDateTime
    WHEN NOT MATCHED
        THEN
            INSERT (
                PersonAliasId
                ,DuplicatePersonAliasId
                ,Score
                ,ScoreDetail
                ,IsConfirmedAsNotDuplicate
                ,ModifiedDateTime
                ,CreatedDateTime
                ,[Guid]
                )
            VALUES (
                source.PersonAliasId
                ,source.DuplicatePersonAliasId
                ,@cScoreWeightName
                ,'|Name'
                ,0
                ,@processDateTime
                ,@processDateTime
                ,NEWID()
                );

    --  Update PersonDuplicate table with results of phonenumber match for each number type. 
    --  For example, if both the Cell and Home phone match, that should be a higher score 
    DECLARE @NumberTypeValueId INT

    DECLARE numberTypeCursor CURSOR FAST_FORWARD
    FOR
    SELECT [Id]
    FROM [DefinedValue]
    WHERE [Id] IN (
            @cHOME_PHONENUMBER_DEFINEDVALUE_ID
            ,@cCELL_PHONENUMBER_DEFINEDVALUE_ID
            )
    ORDER BY [Id]

    OPEN numberTypeCursor

    FETCH NEXT
    FROM numberTypeCursor
    INTO @NumberTypeValueId

    -- loop thru each of the phone number types (home, cell)
    WHILE @@FETCH_STATUS = 0
    BEGIN
        MERGE [PersonDuplicate] AS TARGET
        USING (
            SELECT [e1].[PersonAliasId] [PersonAliasId]
                ,[e2].[PersonAliasId] [DuplicatePersonAliasId]
                ,[e1].[Number]
                ,[e1].[Extension]
                ,[e1].[CountryCode]
                ,[e1].[NumberTypeValueId]
                ,[e1].[Gender]
            FROM #PersonDuplicateByPhoneTable [e1]
            JOIN #PersonDuplicateByPhoneTable [e2] ON [e1].[Number] = [e2].[Number]
                AND [e1].[Extension] = [e2].[Extension]
                AND [e1].[CountryCode] = [e2].[CountryCode]
                AND [e1].[NumberTypeValueId] = [e2].[NumberTypeValueId]
                AND [e1].[Gender] = [e2].[Gender]
                AND [e1].[Id] != [e2].[Id]
                AND [e1].[PersonAliasId] > [e2].[PersonAliasId] -- we only need the matched pair in there once (don't need both PersonA == PersonB and PersonB == PersonA)
            WHERE [e1].[NumberTypeValueId] = @NumberTypeValueId
            ) AS source(PersonAliasId, DuplicatePersonAliasId, Number, Extension, CountryCode, NumberTypeValueId, Gender)
            ON (target.PersonAliasId = source.PersonAliasId)
                AND (target.DuplicatePersonAliasId = source.DuplicatePersonAliasId)
        WHEN MATCHED
            THEN
                UPDATE
                SET [Score] = [Score] + @cScoreWeightPhoneNumber
                    ,[ScoreDetail] += '|Phone'
                    ,[ModifiedDateTime] = @processDateTime
        WHEN NOT MATCHED
            THEN
                INSERT (
                    PersonAliasId
                    ,DuplicatePersonAliasId
                    ,Score
                    ,ScoreDetail
                    ,IsConfirmedAsNotDuplicate
                    ,ModifiedDateTime
                    ,CreatedDateTime
                    ,[Guid]
                    )
                VALUES (
                    source.PersonAliasId
                    ,source.DuplicatePersonAliasId
                    ,@cScoreWeightPhoneNumber
                    ,'|Phone'
                    ,0
                    ,@processDateTime
                    ,@processDateTime
                    ,NEWID()
                    );

        FETCH NEXT
        FROM numberTypeCursor
        INTO @NumberTypeValueId
    END

    CLOSE numberTypeCursor

    DEALLOCATE numberTypeCursor

    -- Update PersonDuplicate table with results of address (location) match
    MERGE [PersonDuplicate] AS TARGET
    USING (
        SELECT [e1].[PersonAliasId] [PersonAliasId]
            ,[e2].[PersonAliasId] [DuplicatePersonAliasId]
            ,[e1].[LocationId]
            ,[e1].[Gender]
            ,[e1].[GroupRoleId]
        FROM #PersonDuplicateByAddressTable [e1]
        JOIN #PersonDuplicateByAddressTable [e2] ON [e1].[LocationId] = [e2].[LocationId]
            AND [e1].[Gender] = [e2].[Gender]
            AND [e1].[GroupRoleId] = [e2].[GroupRoleId]
            AND [e1].[Id] != [e2].[Id]
            AND [e1].[PersonAliasId] > [e2].[PersonAliasId] -- we only need the matched pair in there once (don't need both PersonA == PersonB and PersonB == PersonA)
        ) AS source(PersonAliasId, DuplicatePersonAliasId, LocationId, Gender, GroupRoleId)
        ON (target.PersonAliasId = source.PersonAliasId)
            AND (target.DuplicatePersonAliasId = source.DuplicatePersonAliasId)
    WHEN MATCHED
        THEN
            UPDATE
            SET [Score] = [Score] + @cScoreWeightAddress
                ,[ScoreDetail] += '|Address'
                ,[ModifiedDateTime] = @processDateTime
    WHEN NOT MATCHED
        THEN
            INSERT (
                PersonAliasId
                ,DuplicatePersonAliasId
                ,Score
                ,ScoreDetail
                ,IsConfirmedAsNotDuplicate
                ,ModifiedDateTime
                ,CreatedDateTime
                ,[Guid]
                )
            VALUES (
                source.PersonAliasId
                ,source.DuplicatePersonAliasId
                ,@cScoreWeightAddress
                ,'|Address'
                ,0
                ,@processDateTime
                ,@processDateTime
                ,NEWID()
                );

    /* Calculate Capacities before we do the additional scores
    */
    -- set base capacity to include MaritalStatus and Gender, since everybody has values for those
    UPDATE [PersonDuplicate]
    SET [Capacity] = CASE 
            WHEN @compareByGender = 1
                THEN @cScoreWeightGender
            ELSE 0
            END + CASE 
            WHEN @compareByMaritalStatus = 1
                THEN @cScoreWeightMaritalStatus
            ELSE 0
            END;

    -- increment capacity values for Email, Name, Birthdate (do in one Update statement since these are all person fields)
    UPDATE [PersonDuplicate]
    SET [Capacity] += CASE 
            WHEN @compareByEmail = 1
                AND isnull(p.Email, '') != ''
                THEN @cScoreWeightEmail
            ELSE 0
            END + CASE 
            WHEN @compareByName = 1
                AND (
                    isnull(p.LastName, '') != ''
                    AND (
                        isnull(p.FirstName, '') != ''
                        OR isnull(p.NickName, '') != ''
                        )
                    )
                THEN @cScoreWeightName
            ELSE 0
            END + CASE 
            WHEN @compareByBirthDate = 1
                AND p.BirthDate IS NOT NULL
                THEN @cScoreWeightBirthdate
            ELSE 0
            END
    FROM PersonDuplicate pd
    JOIN PersonAlias pa ON pa.Id = pd.PersonAliasId
    JOIN Person p ON p.Id = pa.PersonId

    -- increment capacity values for Phone
    UPDATE [PersonDuplicate]
    SET [Capacity] += @cScoreWeightPhoneNumber
    FROM PersonDuplicate pd
    JOIN PersonAlias pa ON pa.Id = pd.PersonAliasId
    JOIN Person p ON p.Id = pa.PersonId
    WHERE p.Id IN (
            SELECT PersonId
            FROM PhoneNumber
            WHERE NumberTypeValueId IN (
                    @cHOME_PHONENUMBER_DEFINEDVALUE_ID
                    ,@cCELL_PHONENUMBER_DEFINEDVALUE_ID
                    )
            )
        AND @compareByPhone = 1

    -- increment capacity values for Address, Campus
    UPDATE [PersonDuplicate]
    SET [Capacity] += @cScoreWeightAddress
    FROM PersonDuplicate pd
    JOIN PersonAlias pa ON pa.Id = pd.PersonAliasId
    JOIN Person p ON p.Id = pa.PersonId
    WHERE p.Id IN (
            SELECT PersonId
            FROM [GroupMember] [gm]
            JOIN [Group] [g] ON [gm].[GroupId] = [g].[Id]
            JOIN [GroupLocation] [gl] ON [gl].[GroupId] = [g].[id]
            JOIN [Location] [l] ON [l].[Id] = [gl].[LocationId]
                AND [g].[GroupTypeId] = @cGROUPTYPE_FAMILY_ID
            WHERE [gl].[GroupLocationTypeValueId] = @cLOCATION_TYPE_HOME_ID
            )
        AND @compareByAddress = 1

    -- increment capacity values for Campus
    UPDATE [PersonDuplicate]
    SET [Capacity] += @cScoreWeightCampus
    FROM PersonDuplicate pd
    JOIN PersonAlias pa ON pa.Id = pd.PersonAliasId
    JOIN Person p ON p.Id = pa.PersonId
    WHERE p.Id IN (
            SELECT PersonId
            FROM [GroupMember] [gm]
            JOIN [Group] [g] ON [gm].[GroupId] = [g].[Id]
            WHERE [g].[GroupTypeId] = @cGROUPTYPE_FAMILY_ID
                AND g.CampusId IS NOT NULL
            )
        AND @compareByCampus = 1

    /*
    Add additional scores to people that are already potential matches 
    */
    -- Increment the score on potential matches that have the same birthday
    UPDATE [PersonDuplicate]
    SET [Score] = [Score] + @cScoreWeightBirthdate
        ,[ScoreDetail] += '|Birthdate'
    FROM PersonDuplicate pd
    JOIN PersonAlias pa1 ON pa1.Id = pd.PersonAliasId
    JOIN PersonAlias pa2 ON pa2.Id = pd.DuplicatePersonAliasId
    JOIN Person p1 ON p1.Id = pa1.PersonId
    JOIN Person p2 ON p2.Id = pa2.PersonId
    WHERE p1.BirthDate = p2.BirthDate
        AND @compareByBirthDate = 1

    -- Increment the score on potential matches that have the same gender
    UPDATE [PersonDuplicate]
    SET [Score] = [Score] + @cScoreWeightGender
        ,[ScoreDetail] += '|Gender'
    FROM PersonDuplicate pd
    JOIN PersonAlias pa1 ON pa1.Id = pd.PersonAliasId
    JOIN PersonAlias pa2 ON pa2.Id = pd.DuplicatePersonAliasId
    JOIN Person p1 ON p1.Id = pa1.PersonId
    JOIN Person p2 ON p2.Id = pa2.PersonId
    WHERE p1.Gender = p2.Gender
        AND @compareByGender = 1

    -- Increment the score on potential matches that have the same campus
    UPDATE PersonDuplicate
    SET [Score] = [Score] + @cScoreWeightCampus
        ,[ScoreDetail] += '|Campus'
    FROM PersonDuplicate pd
    JOIN PersonAlias pa1 ON pa1.Id = pd.PersonAliasId
    JOIN PersonAlias pa2 ON pa2.Id = pd.DuplicatePersonAliasId
    JOIN Person p1 ON p1.Id = pa1.PersonId
    JOIN Person p2 ON p2.Id = pa2.PersonId
    JOIN [GroupMember] [gm1] ON [gm1].[PersonId] = [p1].[Id]
    JOIN [Group] [g1] ON [gm1].[GroupId] = [g1].[Id]
    JOIN [GroupMember] [gm2] ON [gm2].[PersonId] = [p2].[Id]
    JOIN [Group] [g2] ON [gm2].[GroupId] = [g2].[Id]
    WHERE g1.CampusId = g2.CampusId
        AND g1.CampusId IS NOT NULL
        AND g2.CampusId IS NOT NULL
        AND [g1].[GroupTypeId] = @cGROUPTYPE_FAMILY_ID
        AND [g2].[GroupTypeId] = @cGROUPTYPE_FAMILY_ID
        AND @compareByCampus = 1

    -- Increment the score on potential matches that have the same marital status
    UPDATE [PersonDuplicate]
    SET [Score] = [Score] + @cScoreWeightMaritalStatus
        ,[ScoreDetail] += '|Marital'
    FROM PersonDuplicate pd
    JOIN PersonAlias pa1 ON pa1.Id = pd.PersonAliasId
    JOIN PersonAlias pa2 ON pa2.Id = pd.DuplicatePersonAliasId
    JOIN Person p1 ON p1.Id = pa1.PersonId
    JOIN Person p2 ON p2.Id = pa2.PersonId
    WHERE p1.MaritalStatusValueId = p2.MaritalStatusValueId
        AND @compareByMaritalStatus = 1

    /* 
    Clean up records that no longer are duplicates 
    */
    DECLARE @staleCount INT;

    SELECT @staleCount = count(*)
    FROM [PersonDuplicate]
    WHERE [ModifiedDateTime] < @processDateTime

    IF (@staleCount != 0)
    BEGIN
        DELETE
        FROM [PersonDuplicate]
        WHERE [ModifiedDateTime] < @processDateTime
    END

    /*
    Explicitly clean up temp tables before the proc exists (vs. have SQL Server do it for us after the proc is done)
    */
    DROP TABLE #PersonDuplicateByEmailTable;

    DROP TABLE #PersonDuplicateByNameTable;

    DROP TABLE #PersonDuplicateByPhoneTable;

    DROP TABLE #PersonDuplicateByAddressTable;

    COMMIT
END
GO

SET STATISTICS TIME ON

EXEC [dbo].[spCrm_PersonDuplicateFinder]
GO

SELECT count(*)
FROM PersonDuplicate
    /*
SELECT PersonAliasId, DuplicatePersonAliasId, Score
    ,Capacity
    ,score / (Capacity * .01) [Percent2]
FROM PersonDuplicate
ORDER BY score / (Capacity * .01) DESC
*/
    -- DEBUG
    /*
SET STATISTICS TIME ON
SET STATISTICS IO ON
GO

EXEC [dbo].[spCrm_PersonDuplicateFinder]
GO

select Len(ScoreDetail) from PersonDuplicate order by Len(ScoreDetail) desc

SELECT p1.FirstName + '|' + p1.NickName + ',' + p1.LastName [Person], p2.FirstName + '|' + p2.NickName  + ', ' +  p2.LastName [DuplicatePerson], Score, ScoreDetail
FROM PersonDuplicate pd
JOIN PersonAlias pa1 ON pa1.Id = pd.PersonAliasId
JOIN PersonAlias pa2 ON pa2.Id = pd.DuplicatePersonAliasId
JOIN Person p1 on p1.Id = pa1.PersonId
JOIN Person p2 on p2.Id = pa2.PersonId
where p1.FirstName != p2.FirstName
order by Score desc, [Person]
*/
