using System.Collections.Generic;
using System.Linq;
using System.Web.Http;
using System.Data.Entity;

using Rock;
using Rock.Data;
using Rock.Model;
using Rock.Web.Cache;
using Rock.Rest;
using Rock.Rest.Filters;
using RouteAttribute = System.Web.Http.RouteAttribute;
using System.Data.SqlClient;

namespace org.newpointe.MiniCheckin.Controllers
{
    public class CheckinController : ApiControllerBase
    {
        [Route( "api/MiniCheckin/GetCheckinDevices" )]
        [HttpGet]
        [Authenticate, Secured]
        public IEnumerable<NamedEntity> GetCheckinDevices()
        {
            DefinedValueCache dvc_KioskDeviceType = DefinedValueCache.Get( Rock.SystemGuid.DefinedValue.DEVICE_TYPE_CHECKIN_KIOSK );
            if (dvc_KioskDeviceType == null) return new List<NamedEntity>();

            return new DeviceService( new RockContext() )
                .Queryable()
                .AsNoTracking()
                .Where( d => d.DeviceTypeValueId == dvc_KioskDeviceType.Id )
                .Select( d => new NamedEntity { Id = d.Id, Name = d.Name } )
                .ToList();
        }

        public class NamedEntity
        {
            public int Id { get; set; }
            public string Name { get; set; }
        }

        [Route( "api/MiniCheckin/GetCheckinConfigurations" )]
        [HttpGet]
        [Authenticate, Secured]
        public IEnumerable<CheckinConfiguration> GetCheckinConfigurations()
        {
            DefinedValueCache dvc_CheckinTemplateGTPurpose = DefinedValueCache.Get( Rock.SystemGuid.DefinedValue.GROUPTYPE_PURPOSE_CHECKIN_TEMPLATE );
            if (dvc_CheckinTemplateGTPurpose == null) return new List<CheckinConfiguration>();

            return new GroupTypeService( new RockContext() )
                .Queryable()
                .AsNoTracking()
                .Where( gt => gt.GroupTypePurposeValueId == dvc_CheckinTemplateGTPurpose.Id )
                .ToList()
                .Select( gt =>
                    {
                        gt.LoadAttributes();
                        return new CheckinConfiguration
                        {
                            Id = gt.Id,
                            Name = gt.Name,
                            AllowCheckout = gt.GetAttributeValue( "core_checkin_AllowCheckout" ).AsBoolean( false )
                        };
                    }
                );
        }

        public class CheckinConfiguration
        {
            public int Id { get; set; }
            public string Name { get; set; }
            public bool AllowCheckout { get; set; }
        }

        [Route( "api/MiniCheckin/GetCheckinAreas" )]
        [HttpGet]
        [Authenticate, Secured]
        public IEnumerable<CheckinArea> GetCheckinAreasFor( int deviceId, int checkinConfigurationId )
        {
            IEnumerable<CheckinArea> deviceCheckinAreas = new GroupTypeService( new RockContext() )
                .ExecuteQuery( SQL_DEVICE_LOCATON_GROUP_TYPES, new SqlParameter( "DeviceId", deviceId ) )
                .AsQueryable()
                .AsNoTracking()
                .Select( gt => new CheckinArea { Id = gt.Id, Name = gt.Name } );

            var configurationCheckinAreaIds = getDecendantGroupTypes( checkinConfigurationId ).Select( gt => gt.Id );

            return deviceCheckinAreas.Select( gt => new CheckinArea { Id = gt.Id, Name = gt.Name, IsPrimary = configurationCheckinAreaIds.Contains( gt.Id ) } );

        }

        private IEnumerable<GroupTypeCache> getDecendantGroupTypes( int parentGroupTypeId )
        {
            GroupTypeCache firstParent = GroupTypeCache.Get( parentGroupTypeId );
            if (firstParent == null) return new List<GroupTypeCache>();

            List<GroupTypeCache> results = new List<GroupTypeCache>();
            Stack<GroupTypeCache> stack = new Stack<GroupTypeCache>();
            stack.Push( firstParent );
            while (stack.Any())
            {
                var next = stack.Pop();
                if (!results.Contains( next ))
                {
                    results.Add( next );
                    foreach (var child in next.ChildGroupTypes) stack.Push( child );
                }
            }

            return results;
        }

        public class CheckinArea
        {
            public int Id { get; set; }
            public string Name { get; set; }
            public bool IsPrimary { get; set; }
        }










        const string SQL_DEVICE_LOCATON_GROUP_TYPES = @"
WITH LocationTree AS (
    SELECT l.Id, l.ParentLocationId
    FROM [Location] l
    WHERE l.Id IN (SELECT dl.LocationId FROM [DeviceLocation] dl WHERE dl.DeviceId = @DeviceId)

    UNION ALL
    
    SELECT l.Id, l.ParentLocationId
    FROM [Location] l
    INNER JOIN LocationTree lt ON l.ParentLocationId = lt.Id
)
SELECT gt.*
FROM (
    SELECT gt.Id
    FROM
        LocationTree lt
        INNER JOIN [GroupLocation] gl ON gl.LocationId = lt.Id
        INNER JOIN [Group] g ON gl.GroupId = g.Id
        INNER JOIN [GroupType] gt ON g.GroupTypeId = gt.Id
    WHERE
        gt.TakesAttendance = 1
    GROUP BY gt.Id
) gtid
INNER JOIN [GroupType] gt ON gt.Id = gtid.Id";

    }
}
