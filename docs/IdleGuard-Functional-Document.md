# IdleGuard: Inactive User Manager

## Functional Document

| Document detail   | Value                                                                                                                       |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Version           | 1.0                                                                                                                         |
| Prepared          | 8 October 2026                                                                                                              |
| Audience          | Business owners, Salesforce administrators, IT operations, security teams, and user acceptance testers                      |
| Scope             | Business problem, intended benefits, and functional behavior of the current implementation                                  |
| Related documents | [Technical Implementation Document](IdleGuard-Technical-Implementation-Document.md) · [Installation Guide](IDLEGUARD.md) |

## 1. Executive overview

IdleGuard helps Salesforce administrators identify dormant user accounts, review whether access is still required, and deactivate approved accounts from one screen. It brings discovery and action into a consistent workflow:

**Filter → Review → Confirm → Deactivate → Review results**

The business objective is to reduce unnecessary access, improve use of available licenses, and reduce the administrative effort involved in account cleanup. Administrators remain responsible for deciding whether an account is safe to deactivate. IdleGuard supplies the information and controls needed to carry out that decision.

In this document, a **dormant user** means an account that is still active in Salesforce but meets the selected inactivity criteria. An account that is already deactivated is not a cleanup candidate.

## 2. Business problem

As an organization grows, Salesforce accounts can remain active after employees leave, contractors finish assignments, or teams stop using the platform. Provisioned accounts may also remain unused because onboarding was delayed or access was never needed.

An administrator may identify these accounts through reports or user records, cross-check them against operational needs, and then open individual accounts to deactivate them. This creates several business challenges.

| Challenge                                                    | Business impact                                                                                                                          |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Unused accounts retain access and license allocations        | Available capacity can be harder to assess, and additional license purchases may be considered before existing allocations are reviewed. |
| Dormant credentials remain enabled                           | Unnecessary access increases the number of accounts the organization must govern and protect.                                            |
| Cleanup requires repeated manual steps                       | Administrators spend time moving between discovery, verification, and individual user updates.                                           |
| Last-login dates are missing for unused accounts             | Users who never logged in can be overlooked, while recently provisioned new hires can be incorrectly flagged.                            |
| Some apparently dormant accounts support critical operations | Deactivating integration, service, or emergency-access accounts can disrupt business processes.                                          |
| A bulk action can encounter mixed outcomes                   | Administrators need to know which accounts changed and which require follow-up.                                                          |

Inactivity is a signal for review, not proof that an account has no business purpose. For example, an emergency account may intentionally be used very rarely.

## 3. Proposed solution and business value

IdleGuard provides a dedicated Lightning screen for reviewing currently active accounts against an administrator-selected inactivity policy. The administrator can select individual candidates or act on the entire displayed list after confirmation.

| Business objective          | How IdleGuard supports it                                                           | Expected outcome                                       |
| --------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------ |
| Improve license utilization | Identify and deactivate accounts whose access is no longer needed                   | More informed reuse of available user-license capacity |
| Reduce unnecessary access   | Apply a repeatable review process to dormant accounts                               | Fewer avoidable active accounts                        |
| Reduce cleanup effort       | Combine filters, review, selection, and deactivation in one screen                  | Less repetitive administration                         |
| Protect business continuity | Exclude designated operational accounts and the administrator performing the action | Lower risk of accidental disruption during cleanup     |
| Improve follow-up           | Show an outcome and explanation for each submitted user                             | Clear ownership of remaining cleanup work              |

These are intended benefits, not measured results from a production rollout. Releasing an account's allocation does not itself reduce a subscription invoice; commercial savings depend on the organization's licensing arrangements and subsequent purchasing decisions.

## 4. Users and responsibilities

| Role                                | Responsibility                                                                               |
| ----------------------------------- | -------------------------------------------------------------------------------------------- |
| Salesforce administrator            | Run searches, review candidates, confirm deactivations, and investigate unsuccessful results |
| Application or integration owner    | Identify accounts needed by integrations, scheduled work, or other operational processes     |
| Security or access-governance owner | Agree review thresholds and identify emergency-access accounts that require protection       |
| Business owner or manager           | Advise whether an individual's access is still required when that decision is unclear        |

Only approved administrators with IdleGuard access and the appropriate native Salesforce permissions can use the action successfully. IdleGuard does not implement a manager-approval workflow. Any required business approval takes place through the organization's existing process before the administrator confirms deactivation.

## 5. Functional scope

### Included in the current implementation

- Search active accounts using days inactive or an inclusive last-login date range.
- Include never-logged-in accounts only after the applicable account-age threshold.
- Display up to 200 matching users for review.
- Show counts for users listed, never-logged-in users listed, and selected users.
- Sort the displayed list by name, profile, last login, or days inactive.
- Deactivate selected users or all users currently listed, following confirmation.
- Protect the running administrator and accounts listed in active exclusion records.
- Recheck eligibility when the action reaches the server.
- Show deactivated, skipped, and failed outcomes, then refresh the candidate list.

### Outside the current scope

IdleGuard does not automatically schedule cleanup, obtain manager approvals, transfer record ownership, resolve automation dependencies, delete accounts, reactivate accounts, remove permission-set assignments, or send user notifications. It does not provide a persistent cleanup-history dashboard, a results export, or license-cost calculations.

Protected integration accounts must be configured explicitly. IdleGuard does not infer every service or integration account from its name or profile.

## 6. Administrator journey

| Step         | Administrator action                                             | System behavior                                                                                        |
| ------------ | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 1. Open      | Open the IdleGuard tab or configured Lightning page              | An authorized user receives an initial search with the default 90-day threshold.                       |
| 2. Filter    | Choose days inactive or a date range, then select **Find users** | The system validates the criteria and returns eligible accounts.                                       |
| 3. Review    | Inspect identity, profile, login history, and inactivity age     | Summary cards and sortable columns help organize the review. User names link to their records.         |
| 4. Select    | Select particular users, or choose **Deactivate all listed**     | The selected action identifies the displayed accounts to submit.                                       |
| 5. Confirm   | Review the account count and consequences; confirm or cancel     | Cancel leaves the accounts unchanged. Confirm submits the request.                                     |
| 6. Process   | Wait for completion                                              | Each submitted account is checked again before an update is attempted.                                 |
| 7. Follow up | Read the result summary and individual explanations              | Successful updates are reflected in a refreshed list. Skipped and failed accounts can be investigated. |

Changing the filter clears the existing list and selection. The administrator must run a new search before acting on the new criteria. This prevents a decision based on one filter from being applied accidentally to an old review list.

## 7. Filtering and display rules

### Days inactive

The administrator enters a whole number from **1 to 3650**. The default is **90**.

A previously used account qualifies when its last login is at or before the current time minus the selected number of days. A never-logged-in account qualifies only when its creation time is strictly earlier than that cutoff. This distinction protects recently provisioned accounts from being flagged simply because no login has occurred yet.

For a 90-day search, an account last used 120 days ago qualifies. A never-used account created 120 days ago also qualifies. A never-used account created 10 days ago does not qualify.

### Date range

The administrator supplies a start date and an end date. Both dates are included, using the running administrator's Salesforce time zone. The start date must not be after the end date, and the end date must not be in the future.

Previously used accounts qualify when their last login falls within the range. Never-logged-in accounts qualify only if they were created before the start date. They have no last-login date to compare directly with the range, so the screen explains this separate age rule.

For example, a range from 1 January through 31 March includes an account last used on 31 March. It also includes a never-used account created before 1 January. A never-used account created during February is excluded.

A date range is not an additional minimum-inactivity rule. A range ending today can include accounts used today; the administrator must choose dates that match the intended review policy.

### Results and summaries

The list shows name, email, profile, last login, login status, and days inactive. For a never-logged-in user, days inactive represents account age. For other users, it represents elapsed whole days since last login.

The never-logged-in count is a subset of the users-listed count. All three summary cards relate to the displayed batch, not an organization-wide total.

Only active accounts are listed. The running administrator and configured protected accounts are excluded.

## 8. Account protection and operational controls

### Protecting operational accounts

An administrator maintains **IdleGuard Exclusion** records in Salesforce Setup. Each active record identifies an account by its User ID, exact username, or both, with an optional reason. An active exclusion remains effective until it is changed or disabled.

| Field          | Example entry or instruction                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------- |
| Label          | `Integration Account`                                                                                         |
| Exclusion Name | `Integration_Account`, normally generated from the label                                                      |
| Active         | Checked                                                                                                       |
| Exact username | Copy the actual Username from the protected user's Salesforce record, including any sandbox suffix.           |
| User ID        | Optional when an exact username is supplied; otherwise use the actual 15- or 18-character Salesforce User ID. |
| Reason         | `Required for integration processing. Do not deactivate.`                                                     |

These example descriptions do not identify a real account. The administrator must supply the organization's actual User ID or username. Email and Username are not necessarily the same value.

If both identity fields are populated, a match to either protects an account. Avoid entering values belonging to different people unless both accounts are deliberately intended to be excluded. Username comparison is case-insensitive. An invalid User ID in an active exclusion blocks processing until corrected.

### Other safeguards

The running administrator cannot deactivate their own account through IdleGuard. Every deactivation action in the screen requires confirmation, and the system rechecks exclusions, active status, and inactivity eligibility before attempting changes.

These checks reduce the risk of acting on an outdated review. They do not replace a business dependency review or guarantee an atomic check against activity occurring at exactly the same time as the update.

## 9. Bulk actions and outcomes

Each search returns at most **200** users. If additional matches exist, a warning is displayed. **Deactivate all listed** acts only on the displayed accounts; it does not silently process all matches in the organization.

There is no Next Page control. After successful deactivations, refreshing the search can bring additional matching users into the displayed batch. The administrator must review and confirm each batch separately. Accounts that remain eligible after a failure may continue to appear, so follow-up on those accounts can be necessary before progressing through a large population.

| Outcome     | Meaning                                                                                                  | Administrator follow-up                                                                    |
| ----------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Deactivated | Salesforce accepted the account update.                                                                  | Verify the expected cleanup outcome.                                                       |
| Skipped     | The account is protected, already inactive, no longer eligible, or no longer available to the operation. | Read the reason; a skipped account did not receive a deactivation update from this action. |
| Failed      | An eligible account was submitted for update but Salesforce rejected it.                                 | Resolve the stated dependency, permission, or validation issue before reviewing it again.  |

One record-level failure does not automatically prevent eligible users in the same operation from being deactivated. A request-level failure can prevent the whole operation from completing.

If deactivation completes but the subsequent refresh fails, the action results remain visible with the refresh error. The administrator should refresh again to obtain a current candidate list.

Results are available in the current component session. They are not saved to a dedicated IdleGuard audit history. Organizations requiring durable evidence should use an agreed external review or evidence-retention process.

## 10. Business acceptance criteria

| ID   | Scenario                                                       | Expected outcome                                                                                  |
| ---- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| F-01 | An approved administrator opens IdleGuard                      | The default 90-day review loads, subject to native Salesforce access.                             |
| F-02 | A user lacks IdleGuard access                                  | The screen explains the access requirement and does not expose the action controls.               |
| F-03 | The administrator enters 0, a fraction, or more than 3650 days | The search is rejected.                                                                           |
| F-04 | A recent new hire has never logged in                          | The account is excluded until it is older than the threshold.                                     |
| F-05 | The administrator searches an inclusive date range             | Qualifying last logins on both boundary dates are included.                                       |
| F-06 | A protected service account matches the inactivity criteria    | It is omitted and remains protected if submitted to the server.                                   |
| F-07 | The running administrator matches the inactivity criteria      | Their account is omitted and cannot be deactivated through the feature.                           |
| F-08 | Filters are changed after users were selected                  | The list and selection clear, requiring a new search.                                             |
| F-09 | The administrator cancels confirmation                         | No deactivation request is submitted by the screen.                                               |
| F-10 | More than 200 users match                                      | The list contains at most 200 users, displays a warning, and limits the bulk action to that list. |
| F-11 | Some accounts cannot be updated                                | Successful, skipped, and failed outcomes are distinguishable with explanations.                   |
| F-12 | An account becomes ineligible before server rechecking         | It is skipped rather than deactivated.                                                            |

These criteria support business acceptance testing. Automated-test evidence and remaining validation limitations are described in the technical document.

## 11. Adoption and measuring value

Before use, the business should agree who can operate IdleGuard, which inactivity thresholds are appropriate, and which accounts need permanent protection. Application owners should review integration and emergency-access accounts with the administrator. Begin with disposable sandbox users before operational use.

The following measures can be recorded during a pilot. They are suggested business measures, not built-in IdleGuard reports or claims of achieved improvement.

| Measure                                    | Suggested interpretation                                                                                         |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| Administrator time per review cycle        | Compare time spent discovering, reviewing, and processing users before and after adoption.                       |
| Accounts successfully deactivated          | Measure completed cleanup, using recorded results or verified user records.                                      |
| Available license capacity by license type | Compare capacity before and after approved cleanup rather than treating every dormant account as a paid license. |
| Outstanding failed actions                 | Track unresolved dependencies and the effort required to resolve them.                                           |
| Protected-account accuracy                 | Periodically confirm that exclusion records still represent valid operational requirements.                      |

## 12. Operational boundaries

IdleGuard supports an access-review process; it does not assess employee status, analyze every form of account activity, or prove that an account is safe to remove. The implementation does not migrate ownership or resolve dependencies. Salesforce's own deactivation restrictions still apply. See [Salesforce's considerations for deactivating users](https://help.salesforce.com/s/articleView?id=sf.users_deactivate_considerations.htm&language=en_US&type=5) when planning operational changes.

This document describes the current source implementation. It does not certify a production rollout or establish whether the package is currently installed in a particular organization.
