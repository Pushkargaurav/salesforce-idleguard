import { LightningElement } from "lwc";
import findUsers from "@salesforce/apex/IdleGuardController.findUsers";
import deactivateUsers from "@salesforce/apex/IdleGuardController.deactivateUsers";
import canManageUsers from "@salesforce/customPermission/IdleGuard_Manage_Users";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

const COLUMNS = [
  {
    label: "Name",
    fieldName: "userUrl",
    type: "url",
    sortable: true,
    typeAttributes: { label: { fieldName: "name" }, target: "_blank" }
  },
  { label: "Email", fieldName: "email", type: "email" },
  { label: "Profile", fieldName: "profileName", type: "text", sortable: true },
  {
    label: "Last login",
    fieldName: "lastLogin",
    type: "date",
    sortable: true,
    typeAttributes: { year: "numeric", month: "short", day: "2-digit" }
  },
  { label: "Login status", fieldName: "loginStatus", type: "text" },
  {
    label: "Days inactive",
    fieldName: "daysInactive",
    type: "number",
    sortable: true
  }
];
const RESULT_COLUMNS = [
  { label: "User", fieldName: "name", type: "text" },
  { label: "Result", fieldName: "status", type: "text", initialWidth: 140 },
  { label: "Details", fieldName: "message", type: "text", wrapText: true }
];

export default class IdleGuard extends LightningElement {
  columns = COLUMNS;
  resultColumns = RESULT_COLUMNS;
  canManageUsers = Boolean(canManageUsers);
  mode = "days";
  daysInactive = 90;
  startDate = "";
  endDate = "";
  users = [];
  selectedIds = [];
  actionResults = [];
  hasMore = false;
  hasSearched = false;
  busy = false;
  errorMessage = "";
  sortedBy = "userUrl";
  sortDirection = "asc";
  appliedFilter;

  connectedCallback() {
    if (this.canManageUsers) {
      this.search();
    }
  }

  get isDaysMode() {
    return this.mode === "days";
  }
  get daysVariant() {
    return this.isDaysMode ? "brand" : "neutral";
  }
  get rangeVariant() {
    return this.isDaysMode ? "neutral" : "brand";
  }
  get userCount() {
    return this.users.length;
  }
  get neverCount() {
    return this.users.filter((user) => user.neverLoggedIn).length;
  }
  get selectedCount() {
    return this.selectedIds.length;
  }
  get hasUsers() {
    return this.userCount > 0;
  }
  get showEmpty() {
    return (
      this.hasSearched && !this.hasUsers && !this.errorMessage && !this.busy
    );
  }
  get selectedDisabled() {
    return this.busy || !this.selectedCount || !this.appliedFilter;
  }
  get allDisabled() {
    return this.busy || !this.userCount || !this.appliedFilter;
  }
  get selectedLabel() {
    return `Deactivate selected (${this.selectedCount})`;
  }
  get allLabel() {
    return `Deactivate all listed (${this.userCount})`;
  }
  get hasActionResults() {
    return this.actionResults.length > 0;
  }
  get resultSummary() {
    const count = (status) =>
      this.actionResults.filter((row) => row.status === status).length;
    return `${count("Deactivated")} deactivated, ${count("Skipped")} skipped, ${count("Failed")} failed.`;
  }
  get filterHelp() {
    return this.isDaysMode
      ? "Never-logged-in users are included only when their account is older than the selected threshold. Their days inactive is their account age."
      : "Both dates are inclusive in your Salesforce time zone. Never-logged-in users are included only if created before the start date; their days inactive is their account age.";
  }

  handleMode(event) {
    if (this.busy || this.mode === event.target.dataset.mode) {
      return;
    }
    this.mode = event.target.dataset.mode;
    this.clearReview();
  }

  handleFilterChange(event) {
    if (this.busy) {
      return;
    }
    const field = event.target.name;
    if (field === "daysInactive") {
      this.daysInactive =
        event.target.value === "" ? null : Number(event.target.value);
    } else if (field === "startDate") {
      this.startDate = event.target.value;
    } else if (field === "endDate") {
      this.endDate = event.target.value;
    }
    this.clearReview();
  }

  clearReview() {
    this.users = [];
    this.selectedIds = [];
    this.hasMore = false;
    this.hasSearched = false;
    this.appliedFilter = undefined;
    this.errorMessage = "";
    this.actionResults = [];
  }

  validateFilter() {
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    const validInputs = inputs
      .map((input) => input.reportValidity())
      .every(Boolean);
    if (!validInputs) {
      return false;
    }
    if (
      this.isDaysMode &&
      (!Number.isInteger(this.daysInactive) ||
        this.daysInactive < 1 ||
        this.daysInactive > 3650)
    ) {
      this.errorMessage =
        "Enter a whole number of inactive days from 1 to 3650.";
      return false;
    }
    if (
      !this.isDaysMode &&
      (!this.startDate || !this.endDate || this.startDate > this.endDate)
    ) {
      this.errorMessage = "Choose a start date on or before the end date.";
      return false;
    }
    return true;
  }

  async search() {
    if (this.busy || !this.validateFilter()) {
      return;
    }
    this.busy = true;
    this.actionResults = [];
    const filter = {
      mode: this.mode,
      daysInactive: this.isDaysMode ? this.daysInactive : null,
      startDate: this.isDaysMode ? null : this.startDate,
      endDate: this.isDaysMode ? null : this.endDate
    };
    try {
      await this.loadUsers(filter);
    } catch (error) {
      this.showError(error);
    } finally {
      this.busy = false;
    }
  }

  async loadUsers(filter) {
    this.errorMessage = "";
    this.selectedIds = [];
    this.users = [];
    this.hasMore = false;
    this.appliedFilter = undefined;
    const response = await findUsers(filter);
    this.users = response.users.map((user) => ({
      ...user,
      userUrl: `/lightning/r/User/${user.userId}/view`,
      loginStatus: user.neverLoggedIn
        ? "Never logged in"
        : "Previously logged in"
    }));
    this.hasMore = response.hasMore;
    this.hasSearched = true;
    this.appliedFilter = { ...filter };
    this.sortRows();
  }

  handleSelection(event) {
    if (this.busy) {
      return;
    }
    this.selectedIds = event.detail.selectedRows.map((row) => row.userId);
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortDirection = event.detail.sortDirection;
    this.sortRows();
  }

  sortRows() {
    const field = this.sortedBy === "userUrl" ? "name" : this.sortedBy;
    const direction = this.sortDirection === "asc" ? 1 : -1;
    this.users = [...this.users].sort((left, right) => {
      const a = left[field];
      const b = right[field];
      if (a == null && b == null) {
        return 0;
      }
      if (a == null) {
        return 1;
      }
      if (b == null) {
        return -1;
      }
      return (
        direction *
        (typeof a === "number" ? a - b : String(a).localeCompare(String(b)))
      );
    });
  }

  handleDeactivateSelected() {
    return this.confirmDeactivation([...this.selectedIds]);
  }
  handleDeactivateAll() {
    return this.confirmDeactivation(this.users.map((user) => user.userId));
  }

  async confirmDeactivation(userIds) {
    if (this.busy || !userIds.length || !this.appliedFilter) {
      return;
    }
    this.busy = true;
    const filter = { ...this.appliedFilter };
    try {
      const confirmed = await LightningConfirm.open({
        label: "Confirm deactivation",
        theme: "error",
        message: `Deactivate ${userIds.length} listed user(s)? They will lose login access and their assigned user licenses will become available. Review record ownership and automation dependencies before proceeding. Protected or newly ineligible users will be skipped.`
      });
      if (!confirmed) {
        return;
      }
      this.actionResults = await deactivateUsers({ userIds, ...filter });
      const hasFailures = this.actionResults.some(
        (row) => row.status === "Failed"
      );
      const hasSkipped = this.actionResults.some(
        (row) => row.status === "Skipped"
      );
      this.toast(
        "Deactivation results",
        this.resultSummary,
        hasFailures || hasSkipped ? "warning" : "success"
      );
      await this.loadUsers(filter);
    } catch (error) {
      this.showError(error);
    } finally {
      this.busy = false;
    }
  }

  showError(error) {
    this.errorMessage =
      error?.body?.message ||
      error?.message ||
      "The request failed. Refresh the list before trying again.";
    this.toast("IdleGuard", this.errorMessage, "error");
  }

  toast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({ title, message, variant, mode: "sticky" })
    );
  }
}
