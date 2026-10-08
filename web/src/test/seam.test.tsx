import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import ComparisonTable from "@/components/fitgap/ComparisonTable";
import FitGapReportPage from "@/pages/fitgap/FitGapReportPage";
import { sessionsApi } from "@/services/sessions";
import { portfoliosApi } from "@/services/portfolios";
import type { FitGapReport, Portfolio, SkillComparison } from "@/types";

// The API returns the axios envelope as plain JSON objects; these aliases keep
// the mocked service responses assignable without spelling out AxiosResponse.
type GetPortfolioResponse = Awaited<ReturnType<typeof sessionsApi.getPortfolio>>;
type GetFitGapResponse = Awaited<ReturnType<typeof portfoliosApi.getFitGap>>;

vi.mock("@/services/sessions", () => ({
  sessionsApi: { getPortfolio: vi.fn() },
}));

vi.mock("@/services/portfolios", () => ({
  portfoliosApi: {
    getFitGap: vi.fn(),
    triggerFitGap: vi.fn(),
    regenerateFitGap: vi.fn(),
    exportPortfolio: vi.fn(),
  },
}));

const getPortfolioMock = vi.mocked(sessionsApi.getPortfolio);
const getFitGapMock = vi.mocked(portfoliosApi.getFitGap);

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

function renderFitGapPage() {
  return render(
    <MemoryRouter initialEntries={["/assessments/1/sessions/2/fitgap/3"]}>
      <Routes>
        <Route
          path="/assessments/:id/sessions/:sessionId/fitgap/:vacancyId"
          element={<FitGapReportPage />}
        />
      </Routes>
    </MemoryRouter>
  );
}

describe("A4 — fit/gap comparison contract (API shape vs web consumer)", () => {
  it("renders the Required column from the API's expected_level key", () => {
    // Payload exactly as FitGap::Engine persists it
    // (api/app/services/fit_gap/engine.rb:58-66): expected_level, no is_override.
    // The web contract expects required_level (web/src/types/index.ts:130-137)
    // and ComparisonTable reads LEVEL_LABELS[c.required_level]
    // (web/src/components/fitgap/ComparisonTable.tsx:50).
    const apiComparison = {
      skill_label: "React",
      expected_level: 3,
      candidate_level: 4,
      result: "exceed",
      delta: 1,
    };

    render(<ComparisonTable comparisons={[apiComparison] as unknown as SkillComparison[]} />);

    const row = screen.getByRole("row", { name: /React/ });
    const [, requiredCell, candidateCell] = within(row).getAllByRole("cell");

    // Today the Required cell is blank: LEVEL_LABELS[undefined] → "".
    expect(requiredCell).toHaveTextContent("L3");
    expect(candidateCell).toHaveTextContent("L4");
  });
});

describe("Portfolio/fit-gap consumer — portfolio skill levels from the real API", () => {
  it("renders a discovered skill's integer ai_level as an L-label", async () => {
    // API serializes portfolio_skills.ai_level as an integer (db/schema.rb:115,
    // portfolios_controller.rb:181); the web type says string but the page
    // renders the raw value (web/src/pages/fitgap/FitGapReportPage.tsx:196).
    const portfolio = {
      id: 10,
      session_id: 2,
      generation_status: "complete",
      skills: [
        {
          id: 1,
          skill_label: "Kubernetes",
          is_discovered: true,
          ai_level: 3 as unknown as string,
          ai_confidence: "high",
          evidence: [],
          competency_summary: "Proficient with Kubernetes.",
        },
      ],
      overrides: [],
    } as Portfolio;

    const report: FitGapReport = {
      id: 20,
      portfolio_id: 10,
      vacancy_id: 3,
      skill_comparisons: [],
      culture_narrative: "Strong culture fit.",
      overall_narrative: "Recommend advancing.",
      generated_at: "2026-01-01T00:00:00Z",
    };

    getPortfolioMock.mockResolvedValue({
      data: { portfolio },
    } as unknown as GetPortfolioResponse);
    getFitGapMock.mockResolvedValue({ data: { report } } as unknown as GetFitGapResponse);

    renderFitGapPage();

    expect(await screen.findByText("Kubernetes")).toBeInTheDocument();
    // Today the discovered-skill line shows the raw integer "3 (confirmed)".
    expect(screen.getByText(/L3/)).toBeInTheDocument();
  });

  it("shows the generating state when GET /sessions/:id/portfolio returns {status:'generating'}", async () => {
    // API: 202 { status: "generating" } when the portfolio is nil/generating
    // (portfolios_controller.rb:13-14). FitGapReportPage only handles
    // { portfolio } (FitGapReportPage.tsx:50-53), so today the page goes blank.
    getPortfolioMock.mockResolvedValue({
      data: { status: "generating" },
    } as unknown as GetPortfolioResponse);

    renderFitGapPage();

    expect(await screen.findByText(/generating/i)).toBeInTheDocument();
  });
});
