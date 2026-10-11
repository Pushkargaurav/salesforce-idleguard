@IsTest
private class IdleGuardControllerTest {
  @TestSetup
  static void setupUsers() {
    Id adminProfile = [
      SELECT Id
      FROM Profile
      WHERE PermissionsManageUsers = TRUE
      LIMIT 1
    ]
    .Id;
    List<User> accounts = new List<User>{
      newUser('admin', adminProfile),
      newUser('old', adminProfile),
      newUser('new', adminProfile),
      newUser('protected', adminProfile),
      newUser('inactive', adminProfile)
    };
    accounts[4].IsActive = false;
    insert accounts;
    Id permissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'IdleGuard_Admin'
      LIMIT 1
    ]
    .Id;
    insert new PermissionSetAssignment(
      AssigneeId = accounts[0].Id,
      PermissionSetId = permissionSet
    );
    for (Integer index : new List<Integer>{ 0, 1, 3, 4 }) {
      Test.setCreatedDate(accounts[index].Id, Datetime.now().addDays(-100));
    }
  }
  private static User newUser(String tag, Id profileId) {
    String suffix =
      UserInfo.getOrganizationId() +
      '.' +
      Datetime.now().getTime() +
      '.' +
      tag;
    return new User(
      LastName = 'IdleGuardTest-' + tag,
      Alias = tag.left(8),
      Email = tag + '@example.com',
      Username = suffix + '@idleguard.example.com',
      ProfileId = profileId,
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }
  private static User account(String tag) {
    return [
      SELECT Id, Name, Username, IsActive, CreatedDate, LastLoginDate, ProfileId
      FROM User
      WHERE LastName = :('IdleGuardTest-' + tag)
      LIMIT 1
    ];
  }
  private static List<IdleGuard_Exclusion__mdt> protect(User account) {
    return new List<IdleGuard_Exclusion__mdt>{
      new IdleGuard_Exclusion__mdt(
        Active__c = true,
        Username__c = account.Username.toUpperCase()
      )
    };
  }
  @IsTest
  static void findsOldNeverLoggedInAccountsAndProtectsAdmin() {
    User admin = account('admin');
    User protectedUser = account('protected');
    System.runAs(admin) {
      IdleGuardController.testExclusions = protect(protectedUser);
      Test.startTest();
      IdleGuardController.SearchResult response = IdleGuardController.findUsers(
        'days',
        90,
        null,
        null
      );
      Test.stopTest();
      Set<Id> found = new Set<Id>();
      for (IdleGuardController.UserRow row : response.users) {
        found.add(row.userId);
        System.assertEquals(true, row.neverLoggedIn);
        System.assert(row.daysInactive >= 90);
      }
      System.assert(found.contains(account('old').Id));
      System.assert(!found.contains(admin.Id));
      System.assert(!found.contains(protectedUser.Id));
      System.assert(!found.contains(account('new').Id));
      System.assert(!found.contains(account('inactive').Id));
      System.assertEquals(200, response.batchLimit);
    }
  }
  @IsTest
  static void dateRangeIncludesOnlyOldNeverLoggedInAccounts() {
    System.runAs(account('admin')) {
      IdleGuardController.testExclusions = new List<IdleGuard_Exclusion__mdt>();
      IdleGuardController.SearchResult response = IdleGuardController.findUsers(
        'range',
        null,
        Date.today().addDays(-90),
        Date.today().addDays(-30)
      );
      Set<Id> found = new Set<Id>();
      for (IdleGuardController.UserRow row : response.users) {
        found.add(row.userId);
      }
      System.assert(found.contains(account('old').Id));
      System.assert(!found.contains(account('new').Id));
    }
  }
  @IsTest
  static void rechecksEverySubmittedIdAndDeactivatesEligibleUsers() {
    User admin = account('admin');
    User oldUser = account('old');
    User protectedUser = account('protected');
    User newUser = account('new');
    User inactive = account('inactive');
    System.runAs(admin) {
      IdleGuardController.testExclusions = protect(protectedUser);
      Test.startTest();
      List<IdleGuardController.ActionResult> results = IdleGuardController.deactivateUsers(
        new List<Id>{
          oldUser.Id,
          admin.Id,
          protectedUser.Id,
          newUser.Id,
          inactive.Id,
          oldUser.Id
        },
        'days',
        90,
        null,
        null
      );
      Test.stopTest();
      Map<Id, String> statuses = new Map<Id, String>();
      for (IdleGuardController.ActionResult result : results) {
        statuses.put(result.userId, result.status);
      }
      System.assertEquals(5, results.size(), 'Duplicate IDs are updated once.');
      System.assertEquals('Deactivated', statuses.get(oldUser.Id));
      for (
        Id protectedId : new List<Id>{
          admin.Id,
          protectedUser.Id,
          newUser.Id,
          inactive.Id
        }
      ) {
        System.assertEquals('Skipped', statuses.get(protectedId));
      }
      System.assertEquals(false, account('old').IsActive);
      System.assertEquals(true, account('admin').IsActive);
      System.assertEquals(true, account('protected').IsActive);
      System.assertEquals(true, account('new').IsActive);
    }
  }
  @IsTest
  static void metadataIdExclusionsAreRecheckedAfterReview() {
    User oldUser = account('old');
    System.runAs(account('admin')) {
      IdleGuardController.testExclusions = new List<IdleGuard_Exclusion__mdt>();
      IdleGuardController.SearchResult before = IdleGuardController.findUsers(
        'days',
        90,
        null,
        null
      );
      System.assert(!before.users.isEmpty());
      IdleGuardController.testExclusions.add(
        new IdleGuard_Exclusion__mdt(
          Active__c = true,
          User_Id__c = String.valueOf(oldUser.Id)
        )
      );
      List<IdleGuardController.ActionResult> results = IdleGuardController.deactivateUsers(
        new List<Id>{ oldUser.Id },
        'days',
        90,
        null,
        null
      );
      System.assertEquals('Skipped', results[0].status);
      System.assertEquals(true, account('old').IsActive);
    }
  }
  @IsTest
  static void disabledExclusionsDoNotProtectUsers() {
    User oldUser = account('old');
    System.runAs(account('admin')) {
      IdleGuardController.testExclusions = new List<IdleGuard_Exclusion__mdt>{
        new IdleGuard_Exclusion__mdt(
          Active__c = false,
          User_Id__c = String.valueOf(oldUser.Id)
        )
      };
      List<IdleGuardController.ActionResult> results = IdleGuardController.deactivateUsers(
        new List<Id>{ oldUser.Id },
        'range',
        null,
        Date.today().addDays(-90),
        Date.today()
      );
      System.assertEquals('Deactivated', results[0].status);
    }
  }
  @IsTest
  static void rejectsUnauthorizedUsers() {
    System.runAs(account('new')) {
      try {
        IdleGuardController.findUsers('days', 90, null, null);
        System.assert(false, 'Custom permission is required for reading.');
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
      }
      try {
        IdleGuardController.deactivateUsers(
          new List<Id>{ account('old').Id },
          'days',
          90,
          null,
          null
        );
        System.assert(false, 'Custom permission is required for writing.');
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('permission'));
      }
    }
  }
  @IsTest
  static void rejectsInvalidFiltersAndRequests() {
    System.runAs(account('admin')) {
      IdleGuardController.testExclusions = new List<IdleGuard_Exclusion__mdt>();
      for (Integer days : new List<Integer>{ null, 0, 3651 }) {
        try {
          IdleGuardController.findUsers('days', days, null, null);
          System.assert(false, 'Invalid threshold should fail.');
        } catch (AuraHandledException error) {
          System.assert(error.getMessage().contains('3650'));
        }
      }
      try {
        IdleGuardController.findUsers('invalid', 90, null, null);
        System.assert(false);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('Choose'));
      }
      try {
        IdleGuardController.findUsers(
          'range',
          null,
          Date.today(),
          Date.today().addDays(-1)
        );
        System.assert(false);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('date range'));
      }
      try {
        IdleGuardController.findUsers(
          'range',
          null,
          Date.today(),
          Date.today().addDays(1)
        );
        System.assert(false);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('date range'));
      }
      List<List<Id>> invalidRequests = new List<List<Id>>{
        null,
        new List<Id>(),
        new List<Id>{ null },
        new List<Id>{ Id.valueOf('001000000000001') }
      };
      List<Id> oversized = new List<Id>();
      Id oldUserId = account('old').Id;
      for (Integer index = 0; index < 201; index++) {
        oversized.add(oldUserId);
      }
      invalidRequests.add(oversized);
      for (List<Id> request : invalidRequests) {
        try {
          IdleGuardController.deactivateUsers(request, 'days', 90, null, null);
          System.assert(false, 'Invalid request should fail.');
        } catch (AuraHandledException error) {
          System.assert(!String.isBlank(error.getMessage()));
        }
      }
    }
  }
  @IsTest
  static void invalidMetadataFailsClosed() {
    System.runAs(account('admin')) {
      for (
        String invalidId : new List<String>{ 'invalid', '001000000000001' }
      ) {
        IdleGuardController.testExclusions = new List<IdleGuard_Exclusion__mdt>{
          new IdleGuard_Exclusion__mdt(Active__c = true, User_Id__c = invalidId)
        };
        try {
          IdleGuardController.findUsers('days', 90, null, null);
          System.assert(false);
        } catch (AuraHandledException error) {
          System.assert(error.getMessage().toLowerCase().contains('exclusion'));
        }
      }
    }
  }
  @IsTest
  static void dateBoundariesAndRecentLoginAreRechecked() {
    Date startDate = Date.today().addDays(-90);
    Date endDate = Date.today().addDays(-30);
    Datetime startTime = Datetime.newInstance(
      startDate,
      Time.newInstance(0, 0, 0, 0)
    );
    Datetime endTime = Datetime.newInstance(
      endDate.addDays(1),
      Time.newInstance(0, 0, 0, 0)
    );
    User synthetic = (User) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{
          'LastLoginDate' => startTime,
          'CreatedDate' => startTime.addDays(-10)
        }
      ),
      User.class
    );
    System.assert(
      IdleGuardController.matchesFilter(
        synthetic,
        'range',
        null,
        startDate,
        endDate
      )
    );
    synthetic = (User) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{ 'LastLoginDate' => endTime.addSeconds(-1) }
      ),
      User.class
    );
    System.assert(
      IdleGuardController.matchesFilter(
        synthetic,
        'range',
        null,
        startDate,
        endDate
      )
    );
    synthetic = (User) JSON.deserialize(
      JSON.serialize(new Map<String, Object>{ 'LastLoginDate' => endTime }),
      User.class
    );
    System.assert(
      !IdleGuardController.matchesFilter(
        synthetic,
        'range',
        null,
        startDate,
        endDate
      )
    );
    synthetic = (User) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{ 'LastLoginDate' => Datetime.now() }
      ),
      User.class
    );
    System.assert(
      !IdleGuardController.matchesFilter(synthetic, 'days', 90, null, null)
    );
    synthetic = (User) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{
          'LastLoginDate' => Datetime.now().addDays(-100)
        }
      ),
      User.class
    );
    System.assert(
      IdleGuardController.matchesFilter(synthetic, 'days', 90, null, null)
    );
  }
  @IsTest
  static void mapsPartialSaveFailuresToTheirUsers() {
    List<Database.SaveResult> saves = (List<Database.SaveResult>) JSON.deserialize(
      '[{"success":true,"errors":[]},{"success":false,"errors":[{"statusCode":"FIELD_INTEGRITY_EXCEPTION","message":"User is required by an automation."}]}]',
      List<Database.SaveResult>.class
    );
    List<IdleGuardController.ActionResult> results = new List<IdleGuardController.ActionResult>();
    List<User> users = new List<User>{ account('old'), account('protected') };
    IdleGuardController.appendSaveResults(results, users, saves);
    System.assertEquals('Deactivated', results[0].status);
    System.assertEquals(users[0].Id, results[0].userId);
    System.assertEquals('Failed', results[1].status);
    System.assertEquals(users[1].Id, results[1].userId);
    System.assert(results[1].message.contains('FIELD_INTEGRITY_EXCEPTION'));
    System.assert(results[1].message.contains('automation'));
  }
  @IsTest
  static void capsResultsAtTwoHundredAndSignalsMore() {
    User admin = account('admin');
    List<User> users = new List<User>();
    for (Integer index = 0; index < 201; index++) {
      User candidate = newUser('batch' + index, admin.ProfileId);
      candidate.LastName = '000IdleGuardBatch-' + index;
      users.add(candidate);
    }
    insert users;
    for (User candidate : users) {
      Test.setCreatedDate(candidate.Id, Datetime.now().addDays(-100));
    }
    System.runAs(admin) {
      IdleGuardController.testExclusions = new List<IdleGuard_Exclusion__mdt>();
      Test.startTest();
      IdleGuardController.SearchResult response = IdleGuardController.findUsers(
        'days',
        90,
        null,
        null
      );
      Test.stopTest();
      System.assertEquals(200, response.users.size());
      System.assertEquals(true, response.hasMore);
      Set<Id> returnedIds = new Set<Id>();
      for (IdleGuardController.UserRow row : response.users) {
        returnedIds.add(row.userId);
      }
      System.assertEquals(200, returnedIds.size());
    }
  }
  @IsTest
  static void customPermissionDoesNotGrantNativeUserAdministration() {
    Id limitedProfile = [
      SELECT Id
      FROM Profile
      WHERE PermissionsManageUsers = FALSE AND UserLicense.Name = 'Salesforce'
      LIMIT 1
    ]
    .Id;
    User limitedUser = newUser('limited', limitedProfile);
    insert limitedUser;
    insert new PermissionSetAssignment(
      AssigneeId = limitedUser.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'IdleGuard_Admin'
        LIMIT 1
      ]
      .Id
    );
    User oldUser = account('old');
    System.runAs(limitedUser) {
      IdleGuardController.testExclusions = new List<IdleGuard_Exclusion__mdt>();
      try {
        List<IdleGuardController.ActionResult> results = IdleGuardController.deactivateUsers(
          new List<Id>{ oldUser.Id },
          'days',
          90,
          null,
          null
        );
        System.assertEquals(1, results.size());
        System.assertNotEquals('Deactivated', results[0].status);
      } catch (AuraHandledException error) {
        System.assert(error.getMessage().contains('access'));
      } catch (QueryException error) {
        System.assert(!String.isBlank(error.getMessage()));
      } catch (DmlException error) {
        System.assert(!String.isBlank(error.getMessage()));
      }
    }
    System.assertEquals(true, account('old').IsActive);
  }
}
