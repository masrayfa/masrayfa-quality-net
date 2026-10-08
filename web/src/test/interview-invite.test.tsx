import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import InterviewPage from "@/pages/interview/InterviewPage";
import { sessionsApi } from "@/services/sessions";

// U1: an invalid/expired invite must never render the "Interview Complete"
// screen. The API answers 404 "invalid or expired" on candidate_info
// (api/app/controllers/api/v1/sessions_controller.rb#candidate_info);
// InterviewPage used to catch() everything straight into "complete".

vi.mock("@/services/sessions", () => ({
  sessionsApi: { getCandidateInfo: vi.fn() },
}));

// The hardware checklist is not what this test exercises; it starts
// timer-driven network probes that would outlive the test.
vi.mock("@/components/HardwareCheck", () => ({ default: () => null }));

const getCandidateInfoMock = vi.mocked(sessionsApi.getCandidateInfo);

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

function renderInterview(token = "expired-token") {
  return render(
    <MemoryRouter initialEntries={[`/interview/${token}`]}>
      <Routes>
        <Route path="/interview/:token" element={<InterviewPage />} />
      </Routes>
    </MemoryRouter>
  );
}

describe("U1 — invalid/expired invite link", () => {
  it("shows an expired-link state on a 404 candidate_info, not the success screen", async () => {
    getCandidateInfoMock.mockRejectedValue({ response: { status: 404 } });

    renderInterview();

    expect(await screen.findByText(/invalid or expired/i)).toBeInTheDocument();
    expect(screen.queryByText(/interview complete/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/has been recorded/i)).not.toBeInTheDocument();
  });

  it("shows an error state (not success) when candidate_info fails for another reason", async () => {
    getCandidateInfoMock.mockRejectedValue({ response: { status: 500 } });

    renderInterview("some-token");

    expect(await screen.findByText(/couldn't load this interview/i)).toBeInTheDocument();
    expect(screen.queryByText(/interview complete/i)).not.toBeInTheDocument();
  });
});
