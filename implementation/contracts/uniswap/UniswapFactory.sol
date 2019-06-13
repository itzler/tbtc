import "../utils/Proxy.sol";
import "./IUniswapFactory.sol";

// IUniswapFactory,
contract UniswapFactory is Proxy {
    constructor(address _instance) public {
        setInstance(_instance);
    }
}