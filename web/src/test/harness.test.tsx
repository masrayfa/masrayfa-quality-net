import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";

// Placeholder: proves vitest + jsdom + RTL + jest-dom matchers are wired.
// Real seam tests land in the next todo.
describe("web test harness", () => {
    it("renders React into jsdom with jest-dom matchers available", () => {
        render(<h1>harness works</h1>);

        expect(screen.getByRole("heading", { name: "harness works" })).toBeInTheDocument();
    });
});
