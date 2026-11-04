import IPv4Addr from "./IPv4Addr";
import "./App.css";
import { apiUrl } from "./Config";

function App() {
  return (
    <div className="App">
      <header className="App-header">
        <div>CIDR Calculator</div>
      </header>
      <IPv4Addr />
      <footer>
        <hr />
        <div className="App-api-status">
          API endpoint: <span data-testid="api-url">{apiUrl} </span>
        </div>
        If you find this tool useful, you might enjoy reading my blog:{" "}
        <a href="https://rderik.com">rderik.com</a>
      </footer>
    </div>
  );
}

export default App;
