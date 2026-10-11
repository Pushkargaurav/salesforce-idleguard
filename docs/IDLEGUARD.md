# IdleGuard: Inactive User Manager

IdleGuard is a native Salesforce Lightning Web Component backed by Apex. It finds active but dormant users, protects the running administrator and configured accounts, and deactivates up to 200 reviewed users per confirmed action.

## Documentation

- [Functional Document](IdleGuard-Functional-Document.md): business problem, solution, administrator workflow, business rules, and acceptance criteria.
- [Technical Implementation Document](IdleGuard-Technical-Implementation-Document.md): architecture, data model, Apex contracts, security, UI behavior, deployment, and test evidence.

## Install

The manifest includes the complete standalone IdleGuard feature. Salesforce API version 67.0 is required by the metadata in this project.

Validate against your sandbox first:

```powershell
sf project deploy start --manifest manifest/idleguard-package.xml --target-org YOUR_SANDBOX --dry-run --test-level RunSpecifiedTests --tests IdleGuardControllerTest --wait 10
```

Deploy:

```powershell
sf project deploy start --manifest manifest/idleguard-package.xml --target-org YOUR_SANDBOX --test-level RunSpecifiedTests --tests IdleGuardControllerTest --wait 10
```

1. In Setup → Permission Sets, assign **IdleGuard Administrator** to the approved administrator. The permission set grants the component's Apex/custom permission and tab access. The administrator must already have native Salesforce permission to manage the target users; this permission set does not grant those privileges.
2. In Setup → Custom Metadata Types → **IdleGuard Exclusion** → Manage Records, add an active record for each integration, service, and break-glass account. Supply its 15- or 18-character User ID, exact username, or both. If both are populated, either value protects a user. Username comparison is case-insensitive. Add a reason for future administrators.
3. Add the **IdleGuard** tab to your Lightning app through App Manager, or drag **IdleGuard: Inactive User Manager** onto a Lightning App Page or Home Page in Lightning App Builder and activate the page.
4. Open IdleGuard and review the configured exclusions before confirming any action.

Exclusion records contain org-specific identities and are not prepopulated. Sandbox username suffixes must match the sandbox account. Active exclusions persist until an administrator changes or disables them. Invalid User IDs fail closed and prevent actions until corrected.

## Filtering and review

- **Days inactive:** integer from 1–3650; default 90. A previous login must be at or before the current time minus N days. A never-logged-in account must have been created strictly before that cutoff.
- **Date range:** both dates are inclusive in the running Salesforce user's time zone. The end date cannot be in the future. Previous logins must fall in the range. A never-logged-in account is included only when created before the start date.
- **Days inactive column:** whole elapsed 24-hour periods since last login, or since account creation for never-logged-in users. Login status is shown explicitly so a blank date is not ambiguous.
- Only active accounts are candidates. The running administrator and active metadata exclusions are omitted from search and rechecked during deactivation.
- The query fetches at most 201 users, ordered by name and ID, and returns the first 200. A warning indicates additional matches; summary cards count only the displayed batch. Sorting rearranges that displayed batch.
- Changing any filter clears the reviewed list and selection. Select **Find users** to apply the new filter.

**Deactivate selected** submits the selected displayed IDs. **Deactivate all listed** submits only the displayed IDs. Both require a Salesforce confirmation dialog. After the action, the component shows a result for every unique submitted user and refreshes the list. If more users match, review the next batch separately.

## Authorization and safety

Both Apex entry points require the `IdleGuard_Manage_Users` custom permission, User object access, and update access to `User.IsActive`. Queries and DML explicitly run in user mode, with sharing enforced, so native Salesforce access remains authoritative. Client IDs, active status, inactivity and metadata exclusions are revalidated on the server for every update.

The User object does not support `FOR UPDATE`. Eligibility is reread immediately before DML, but Salesforce does not provide an atomic lock against a concurrent login or metadata edit through this query. LastLoginDate is a login timestamp, not a complete measure of business activity; maintain exclusions for service accounts.

`Database.update(..., false, AccessLevel.USER_MODE)` permits per-user success and failure. Salesforce dependency/validation errors are displayed beside the affected user. Deactivation does not transfer owned records, remove automation dependencies, delete users, or remove permission-set assignments. Review those dependencies before confirming. Unexpected transaction-level failures roll back the transaction and appear as an error.

Results are shown for the current operation in the component; this implementation does not create a separate persistent audit log. Existing Salesforce auditing remains available.

## Files

- `force-app/main/default/lwc/idleGuard/`: component, styles and Jest tests.
- `force-app/main/default/classes/IdleGuardController.cls`: filtering, authorization and deactivation.
- `force-app/main/default/classes/IdleGuardControllerTest.cls`: Apex safety and boundary tests.
- `force-app/main/default/objects/IdleGuard_Exclusion__mdt/`: administrator-managed account exclusions.
- `force-app/main/default/permissionsets/IdleGuard_Admin.permissionset-meta.xml`: opt-in administrator access.
- `manifest/idleguard-package.xml`: isolated deployment manifest.

## Local verification

```powershell
npm install
npm run test:unit -- --runInBand idleGuard
npx eslint force-app/main/default/lwc/idleGuard
```

Apex tests run in Salesforce through the validation command above. Test-created users and changes are rolled back by the Apex test framework.

The Jest suite uses Salesforce base-component mocks; it checks orchestration and safety states, not rendered Salesforce styling. After deployment, verify the tab in Lightning Experience, confirm sorting and keyboard navigation, and exercise deactivation only with disposable sandbox users.

## Salesforce references

- [User-mode CRUD and field-level security](https://developer.salesforce.com/docs/platform/secure-coding/guide/secure-coding-access-control-protect-from-crud-fls-vulnerabilities.html)
- [Lightning confirmation dialogs](https://developer.salesforce.com/docs/platform/lightning-component-reference/guide/lightning-confirm.html)
- [Considerations for deactivating users](https://help.salesforce.com/s/articleView?id=sf.users_deactivate_considerations.htm&language=en_US&type=5)
