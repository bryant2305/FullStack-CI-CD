import { render, screen } from "@testing-library/react";
import App from "./App";
import {apiUrl} from "./Config";
  
test("renders learn react link", () => {
  render(<App />);
  const linkElement = screen.getByText(/CIDR Calculator/i);
  expect(linkElement).toBeInTheDocument();
});

test("displays the API endpoint URL", () => {
  render(<App />);
  const apiUrlElement = screen.getByTestId("api-url");
  expect(apiUrlElement).toHaveTextContent(apiUrl);
});
