import "../utils/Proxy.sol";
import "./IUniswapExchange.sol";

// IUniswapExchange,
contract UniswapExchange is Proxy {
    constructor(address _instance) public {
        setInstance(_instance);
    }
}