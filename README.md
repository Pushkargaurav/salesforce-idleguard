# IdleGuard for Salesforce

Find dormant Salesforce users, protect configured accounts, and deactivate reviewed users with confirmation.

This standalone Salesforce DX repository includes the Lightning Web Component, Apex controller and tests, permission set, tab, and deployment manifest.

## Requirements

- Salesforce org supporting metadata API 67.0 and Lightning Experience.
- Salesforce CLI and deployment permissions in the target org.
- Node.js and npm for local Jest tests and lint checks.

## Install

Authenticate your sandbox (use https://login.salesforce.com for a production or Developer Edition org):

~~~~sh
sf org login web --instance-url https://test.salesforce.com --alias YOUR_SANDBOX
~~~~

Validate before installing:

~~~~sh
sf project deploy start --dry-run --manifest manifest/idleguard-package.xml --target-org YOUR_SANDBOX --test-level RunSpecifiedTests --tests IdleGuardControllerTest --wait 10
~~~~

Deploy and assign access:

~~~~sh
sf project deploy start --manifest manifest/idleguard-package.xml --target-org YOUR_SANDBOX --test-level RunSpecifiedTests --tests IdleGuardControllerTest --wait 10
sf org assign permset --name IdleGuard_Admin --target-org YOUR_SANDBOX
~~~~

Add the IdleGuard tab to your Lightning app using App Manager, or place the component on an App Page or Home Page. Configure protected accounts under Setup > Custom Metadata Types > IdleGuard Exclusion > Manage Records. Administrators must already have Salesforce privileges to manage users. Verify deactivation with disposable sandbox users before operational use.

## Local checks

~~~~sh
npm install
npm run test:unit -- --runInBand
npm run lint
~~~~

Apex tests run through Salesforce deployment validation. Local checks require installing the development dependencies.

## Documentation

See the [IdleGuard installation and usage guide](docs/IDLEGUARD.md).

- [Functional document](docs/IdleGuard-Functional-Document.md)
- [Technical implementation](docs/IdleGuard-Technical-Implementation-Document.md)

