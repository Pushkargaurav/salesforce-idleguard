public with sharing class IdleGuardController {
  private static final Integer BATCH_LIMIT = 200;
  @TestVisible
  private static List<IdleGuard_Exclusion__mdt> testExclusions;

  public class UserRow {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String profileName;
    @AuraEnabled
    public Datetime lastLogin;
    @AuraEnabled
    public Integer daysInactive;
    @AuraEnabled
    public Boolean neverLoggedIn;
    public UserRow(User account) {
      userId = account.Id;
      name = account.Name;
      email = account.Email;
      profileName = account.Profile.Name;
      lastLogin = account.LastLoginDate;
      neverLoggedIn = lastLogin == null;
      Datetime reference = neverLoggedIn ? account.CreatedDate : lastLogin;
      daysInactive = Integer.valueOf(
        (Datetime.now().getTime() - reference.getTime()) / 86400000
      );
    }
  }
  public class SearchResult {
    @AuraEnabled
    public List<UserRow> users = new List<UserRow>();
    @AuraEnabled
    public Boolean hasMore = false;
    @AuraEnabled
    public Integer batchLimit = BATCH_LIMIT;
  }
  public class ActionResult {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String message;
    public ActionResult(Id userId, String name, String status, String message) {
      this.userId = userId;
      this.name = name;
      this.status = status;
      this.message = message;
    }
  }
  private class Filter {
    Datetime cutoff;
    Datetime startTime;
    Datetime endTime;
    Filter(String mode, Integer daysInactive, Date startDate, Date endDate) {
      if (mode == 'days') {
        if (daysInactive == null || daysInactive < 1 || daysInactive > 3650) {
          throw handled(
            'Enter a whole number of inactive days from 1 to 3650.'
          );
        }
        cutoff = Datetime.now().addDays(-daysInactive);
      } else if (mode == 'range') {
        if (
          startDate == null ||
          endDate == null ||
          startDate > endDate ||
          endDate > Date.today()
        ) {
          throw handled('Choose a valid date range ending on or before today.');
        }
        startTime = Datetime.newInstance(
          startDate,
          Time.newInstance(0, 0, 0, 0)
        );
        endTime = Datetime.newInstance(
          endDate.addDays(1),
          Time.newInstance(0, 0, 0, 0)
        );
        cutoff = startTime;
      } else {
        throw handled('Choose Days inactive or Date range.');
      }
    }
  }
  private class Exclusions {
    Set<Id> userIds = new Set<Id>();
    Set<String> usernames = new Set<String>();
    Exclusions() {
      List<IdleGuard_Exclusion__mdt> records = testExclusions == null
        ? IdleGuard_Exclusion__mdt.getAll().values()
        : testExclusions;
      for (IdleGuard_Exclusion__mdt rule : records) {
        if (!rule.Active__c) {
          continue;
        }
        if (!String.isBlank(rule.User_Id__c)) {
          try {
            Id userId = Id.valueOf(rule.User_Id__c.trim());
            if (userId.getSObjectType() != User.SObjectType) {
              throw handled(
                'An IdleGuard exclusion contains an invalid User ID.'
              );
            }
            userIds.add(userId);
          } catch (Exception error) {
            throw handled(
              'Correct the invalid User ID in IdleGuard Exclusions before continuing.'
            );
          }
        }
        if (!String.isBlank(rule.Username__c)) {
          usernames.add(rule.Username__c.trim().toLowerCase());
        }
      }
    }
    Boolean contains(User account) {
      return userIds.contains(account.Id) ||
        usernames.contains(account.Username.toLowerCase());
    }
  }

  // Intentionally uncached: each review must use current login and exclusion data.
  @AuraEnabled
  public static SearchResult findUsers(
    String mode,
    Integer daysInactive,
    Date startDate,
    Date endDate
  ) {
    requireAccess();
    Filter filter = new Filter(mode, daysInactive, startDate, endDate);
    Exclusions exclusions = new Exclusions();
    Id runningUser = UserInfo.getUserId();
    Set<Id> excludedIds = exclusions.userIds;
    Set<String> excludedNames = exclusions.usernames;
    Datetime cutoff = filter.cutoff;
    Datetime startTime = filter.startTime;
    Datetime endTime = filter.endTime;
    List<User> accounts;
    if (mode == 'days') {
      accounts = [
        SELECT
          Id,
          Name,
          Email,
          Username,
          Profile.Name,
          LastLoginDate,
          CreatedDate,
          IsActive
        FROM User
        WHERE
          IsActive = TRUE
          AND Id != :runningUser
          AND Id NOT IN :excludedIds
          AND Username NOT IN :excludedNames
          AND ((LastLoginDate != NULL
          AND LastLoginDate <= :cutoff)
          OR (LastLoginDate = NULL
          AND CreatedDate < :cutoff))
        WITH USER_MODE
        ORDER BY Name, Id
        LIMIT 201
      ];
    } else {
      accounts = [
        SELECT
          Id,
          Name,
          Email,
          Username,
          Profile.Name,
          LastLoginDate,
          CreatedDate,
          IsActive
        FROM User
        WHERE
          IsActive = TRUE
          AND Id != :runningUser
          AND Id NOT IN :excludedIds
          AND Username NOT IN :excludedNames
          AND ((LastLoginDate >= :startTime
          AND LastLoginDate < :endTime)
          OR (LastLoginDate = NULL
          AND CreatedDate < :cutoff))
        WITH USER_MODE
        ORDER BY Name, Id
        LIMIT 201
      ];
    }
    SearchResult response = new SearchResult();
    response.hasMore = accounts.size() > BATCH_LIMIT;
    for (
      Integer index = 0; index < Math.min(accounts.size(), BATCH_LIMIT); index++
    ) {
      response.users.add(new UserRow(accounts[index]));
    }
    return response;
  }

  @AuraEnabled
  public static List<ActionResult> deactivateUsers(
    List<Id> userIds,
    String mode,
    Integer daysInactive,
    Date startDate,
    Date endDate
  ) {
    requireAccess();
    Filter filter = new Filter(mode, daysInactive, startDate, endDate);
    if (userIds == null || userIds.isEmpty() || userIds.size() > BATCH_LIMIT) {
      throw handled('Submit between 1 and 200 displayed users per action.');
    }
    Set<Id> requested = new Set<Id>(userIds);
    for (Id userId : requested) {
      if (userId == null || userId.getSObjectType() != User.SObjectType) {
        throw handled('Only valid Salesforce User IDs are accepted.');
      }
    }
    Exclusions exclusions = new Exclusions();
    Map<Id, User> accounts = new Map<Id, User>(
      [
        SELECT Id, Name, Username, LastLoginDate, CreatedDate, IsActive
        FROM User
        WHERE Id IN :requested
        WITH USER_MODE
      ]
    );
    List<ActionResult> results = new List<ActionResult>();
    List<User> updates = new List<User>();
    List<User> eligible = new List<User>();
    Set<Id> processed = new Set<Id>();
    for (Id userId : userIds) {
      if (processed.contains(userId)) {
        continue;
      }
      processed.add(userId);
      User account = accounts.get(userId);
      String reason;
      if (userId == UserInfo.getUserId()) {
        reason = 'The running administrator is protected.';
      } else if (account == null) {
        reason = 'User no longer exists or is not accessible.';
      } else if (exclusions.contains(account)) {
        reason = 'User is protected by an IdleGuard exclusion.';
      } else if (!account.IsActive) {
        reason = 'User is already inactive.';
      } else if (!matches(account, filter)) {
        reason = 'User no longer meets the inactivity filter.';
      }
      if (reason != null) {
        results.add(
          new ActionResult(
            userId,
            account == null ? String.valueOf(userId) : account.Name,
            'Skipped',
            reason
          )
        );
      } else {
        eligible.add(account);
        updates.add(new User(Id = userId, IsActive = false));
      }
    }
    if (!updates.isEmpty()) {
      appendSaveResults(
        results,
        eligible,
        Database.update(updates, false, AccessLevel.USER_MODE)
      );
    }
    return results;
  }

  @TestVisible
  private static Boolean matches(User account, Filter filter) {
    if (account.LastLoginDate == null) {
      return account.CreatedDate < filter.cutoff;
    }
    return filter.startTime == null
      ? account.LastLoginDate <= filter.cutoff
      : account.LastLoginDate >= filter.startTime &&
        account.LastLoginDate < filter.endTime;
  }
  @TestVisible
  private static Boolean matchesFilter(
    User account,
    String mode,
    Integer days,
    Date startDate,
    Date endDate
  ) {
    return matches(account, new Filter(mode, days, startDate, endDate));
  }
  @TestVisible
  private static void appendSaveResults(
    List<ActionResult> results,
    List<User> eligible,
    List<Database.SaveResult> saves
  ) {
    for (Integer index = 0; index < saves.size(); index++) {
      Database.SaveResult saved = saves[index];
      List<String> errors = new List<String>();
      for (Database.Error error : saved.getErrors()) {
        errors.add(
          String.valueOf(error.getStatusCode()) + ': ' + error.getMessage()
        );
      }
      results.add(
        new ActionResult(
          eligible[index].Id,
          eligible[index].Name,
          saved.isSuccess() ? 'Deactivated' : 'Failed',
          saved.isSuccess()
            ? 'User access has been deactivated.'
            : String.join(errors, '; ')
        )
      );
    }
  }
  private static void requireAccess() {
    if (
      !FeatureManagement.checkPermission('IdleGuard_Manage_Users') ||
      !Schema.sObjectType.User.isAccessible() ||
      !Schema.sObjectType.User.isUpdateable() ||
      !Schema.sObjectType.User.fields.IsActive.isUpdateable()
    ) {
      throw handled(
        'IdleGuard requires its administrator permission set and Salesforce user-management access.'
      );
    }
  }
  private static AuraHandledException handled(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}
