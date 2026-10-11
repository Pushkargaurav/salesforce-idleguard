import { setImmediate } from "timers";
import { createElement } from "lwc";
import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
  jest
} from "@jest/globals";
import IdleGuard from "c/idleGuard";
import findUsers from "@salesforce/apex/IdleGuardController.findUsers";
import deactivateUsers from "@salesforce/apex/IdleGuardController.deactivateUsers";
import LightningConfirm from "lightning/confirm";

jest.mock(
  "@salesforce/apex/IdleGuardController.findUsers",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/IdleGuardController.deactivateUsers",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/IdleGuard_Manage_Users",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock("lightning/confirm", () => ({ open: jest.fn() }), { virtual: true });

const USERS = [
  {
    userId: "005000000000001AAA",
    name: "Zoe",
    email: "zoe@example.com",
    profileName: "Standard User",
    lastLogin: "2025-01-01T12:00:00.000Z",
    daysInactive: 300,
    neverLoggedIn: false
  },
  {
    userId: "005000000000002AAA",
    name: "Alex",
    email: "alex@example.com",
    profileName: "System Administrator",
    lastLogin: null,
    daysInactive: 100,
    neverLoggedIn: true
  }
];
const flush = () => new Promise((resolve) => setImmediate(resolve));
const mount = () => {
  const element = createElement("c-idle-guard", { is: IdleGuard });
  document.body.appendChild(element);
  return element;
};
const button = (element, action) =>
  element.shadowRoot.querySelector(`[data-action="${action}"]`);
const reviewTable = (element) =>
  element.shadowRoot.querySelector("lightning-datatable");
const clickSearch = (element) => {
  element.shadowRoot.querySelectorAll("lightning-input").forEach((input) => {
    input.reportValidity = jest.fn().mockReturnValue(true);
  });
  element.shadowRoot.querySelector(".find-button").click();
};

describe("c-idle-guard", () => {
  beforeEach(() => {
    findUsers.mockResolvedValue({ users: USERS, hasMore: false });
    LightningConfirm.open.mockResolvedValue(true);
    deactivateUsers.mockResolvedValue([]);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.resetAllMocks();
  });

  it("loads the default threshold, displays summaries, and sorts names", async () => {
    const element = mount();
    await flush();
    expect(findUsers).toHaveBeenCalledWith({
      mode: "days",
      daysInactive: 90,
      startDate: null,
      endDate: null
    });
    expect(reviewTable(element).data.map((row) => row.name)).toEqual([
      "Alex",
      "Zoe"
    ]);
    expect(
      [...element.shadowRoot.querySelectorAll(".summary-number")].map(
        (card) => card.textContent
      )
    ).toEqual(["2", "1", "0"]);
    expect(button(element, "selected").disabled).toBe(true);
    expect(button(element, "all").disabled).toBe(false);
  });

  it("requires confirmation and performs no update when cancelled", async () => {
    LightningConfirm.open.mockResolvedValue(false);
    const element = mount();
    await flush();
    button(element, "all").click();
    await flush();
    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({ label: "Confirm deactivation", theme: "error" })
    );
    expect(deactivateUsers).not.toHaveBeenCalled();
    expect(button(element, "all").disabled).toBe(false);
  });

  it("sends only selected IDs with the reviewed filter and shows partial results", async () => {
    const element = mount();
    await flush();
    reviewTable(element).dispatchEvent(
      new CustomEvent("rowselection", { detail: { selectedRows: USERS } })
    );
    await flush();
    deactivateUsers.mockResolvedValue([
      {
        userId: USERS[0].userId,
        name: "Zoe",
        status: "Deactivated",
        message: "Deactivated."
      },
      {
        userId: USERS[1].userId,
        name: "Alex",
        status: "Failed",
        message: "Required by an automation."
      }
    ]);
    findUsers.mockResolvedValue({ users: [USERS[1]], hasMore: false });
    button(element, "selected").click();
    await flush();
    expect(deactivateUsers).toHaveBeenCalledWith({
      userIds: USERS.map((row) => row.userId),
      mode: "days",
      daysInactive: 90,
      startDate: null,
      endDate: null
    });
    expect(
      element.shadowRoot.querySelector(".result-summary").textContent
    ).toBe("1 deactivated, 0 skipped, 1 failed.");
    expect(
      element.shadowRoot.querySelectorAll("lightning-datatable")[1].data[1]
        .message
    ).toBe("Required by an automation.");
    expect(reviewTable(element).data).toHaveLength(1);
    expect(button(element, "selected").disabled).toBe(true);
  });

  it("deactivates all and only the displayed IDs, and warns about additional matches", async () => {
    findUsers.mockResolvedValue({ users: USERS, hasMore: true });
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector(".warning").textContent).toContain(
      "More than 200 users match"
    );
    button(element, "all").click();
    await flush();
    expect(deactivateUsers.mock.calls[0][0].userIds).toEqual([
      USERS[1].userId,
      USERS[0].userId
    ]);
    expect(deactivateUsers.mock.calls[0][0]).not.toHaveProperty(
      "deactivateAll"
    );
  });

  it("invalidates the reviewed list and selection when the threshold changes", async () => {
    const element = mount();
    await flush();
    reviewTable(element).dispatchEvent(
      new CustomEvent("rowselection", { detail: { selectedRows: [USERS[0]] } })
    );
    await flush();
    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "30";
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(reviewTable(element)).toBeNull();
    expect(button(element, "all").disabled).toBe(true);
    expect(button(element, "selected").disabled).toBe(true);
    clickSearch(element);
    await flush();
    expect(findUsers).toHaveBeenLastCalledWith({
      mode: "days",
      daysInactive: 30,
      startDate: null,
      endDate: null
    });
  });

  it.each(["0", "3651", "1.5", ""])(
    "rejects invalid threshold %s before a server request",
    async (value) => {
      const element = mount();
      await flush();
      const input = element.shadowRoot.querySelector("lightning-input");
      input.value = value;
      input.dispatchEvent(new CustomEvent("change"));
      await flush();
      clickSearch(element);
      await flush();
      expect(findUsers).toHaveBeenCalledTimes(1);
      expect(element.shadowRoot.querySelector(".error").textContent).toContain(
        "whole number"
      );
    }
  );

  it("submits date range mode and clears stale review state on mode changes", async () => {
    const element = mount();
    await flush();
    element.shadowRoot.querySelector('[data-mode="range"]').click();
    await flush();
    expect(button(element, "all").disabled).toBe(true);
    const start = [
      ...element.shadowRoot.querySelectorAll("lightning-input")
    ].find((input) => input.name === "startDate");
    start.value = "2025-01-01";
    start.dispatchEvent(new CustomEvent("change"));
    const end = [
      ...element.shadowRoot.querySelectorAll("lightning-input")
    ].find((input) => input.name === "endDate");
    end.value = "2025-03-31";
    end.dispatchEvent(new CustomEvent("change"));
    await flush();
    clickSearch(element);
    await flush();
    expect(findUsers).toHaveBeenLastCalledWith({
      mode: "range",
      daysInactive: null,
      startDate: "2025-01-01",
      endDate: "2025-03-31"
    });
  });

  it("sorts numeric days and keeps missing login dates last", async () => {
    const element = mount();
    await flush();
    reviewTable(element).dispatchEvent(
      new CustomEvent("sort", {
        detail: { fieldName: "daysInactive", sortDirection: "desc" }
      })
    );
    await flush();
    expect(reviewTable(element).data[0].name).toBe("Zoe");
    reviewTable(element).dispatchEvent(
      new CustomEvent("sort", {
        detail: { fieldName: "lastLogin", sortDirection: "asc" }
      })
    );
    await flush();
    expect(reviewTable(element).data[1].lastLogin).toBeNull();
  });

  it("displays a clear empty state", async () => {
    findUsers.mockResolvedValue({ users: [], hasMore: false });
    const element = mount();
    await flush();
    expect(
      element.shadowRoot.querySelector(".empty-state").textContent
    ).toContain("No eligible inactive users");
    expect(button(element, "all").disabled).toBe(true);
  });

  it("displays server errors and prevents acting on a failed search", async () => {
    findUsers.mockRejectedValue({ body: { message: "Access denied." } });
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector(".error").textContent).toBe(
      "Access denied."
    );
    expect(button(element, "all").disabled).toBe(true);
  });

  it("retains action results if refreshing the list fails", async () => {
    const element = mount();
    await flush();
    deactivateUsers.mockResolvedValue([
      {
        userId: USERS[0].userId,
        name: "Zoe",
        status: "Skipped",
        message: "Recently logged in."
      }
    ]);
    findUsers.mockRejectedValue({ body: { message: "Refresh failed." } });
    button(element, "all").click();
    await flush();
    expect(
      element.shadowRoot.querySelector(".result-summary").textContent
    ).toContain("1 skipped");
    expect(element.shadowRoot.querySelector(".error").textContent).toBe(
      "Refresh failed."
    );
    expect(button(element, "all").disabled).toBe(true);
  });

  it("prevents duplicate submissions while confirmation is pending", async () => {
    let resolveConfirmation;
    LightningConfirm.open.mockReturnValue(
      new Promise((resolve) => {
        resolveConfirmation = resolve;
      })
    );
    const element = mount();
    await flush();
    button(element, "all").click();
    button(element, "all").click();
    await flush();
    expect(LightningConfirm.open).toHaveBeenCalledTimes(1);
    expect(button(element, "all").disabled).toBe(true);
    resolveConfirmation(false);
    await flush();
    expect(deactivateUsers).not.toHaveBeenCalled();
  });
});
