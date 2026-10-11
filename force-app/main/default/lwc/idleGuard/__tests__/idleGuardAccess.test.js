import { createElement } from "lwc";
import { describe, it, expect, afterEach, jest } from "@jest/globals";
import IdleGuard from "c/idleGuard";
import findUsers from "@salesforce/apex/IdleGuardController.findUsers";
import deactivateUsers from "@salesforce/apex/IdleGuardController.deactivateUsers";

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
  () => ({ default: false }),
  { virtual: true }
);

describe("IdleGuard access", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.resetAllMocks();
  });
  it("does not fetch users or expose deactivation controls without the custom permission", async () => {
    const element = createElement("c-idle-guard", { is: IdleGuard });
    document.body.appendChild(element);
    await Promise.resolve();
    expect(element.shadowRoot.querySelector(".notice").textContent).toContain(
      "IdleGuard Administrator permission set"
    );
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
    expect(element.shadowRoot.querySelector('[data-action="all"]')).toBeNull();
    expect(findUsers).not.toHaveBeenCalled();
    expect(deactivateUsers).not.toHaveBeenCalled();
  });
});
