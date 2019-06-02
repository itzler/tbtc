pragma solidity 0.4.25;

import "../vendor/roles.sol";
// import "../price-oracle/PriceOracleV1.sol";

contract TBTCSystem {
    DSRoles authority;
    
    IPriceOracle priceOracle;

    constructor() {

    }

    setup() public {
        authority = new DSRoles();
        authority.setRootUser(this, true);
        
        // Create price oracle
        // Dependency inversion is used here.
        // priceOracle.setAuthority(authority)
        // priceOracle.setOwner(this)
        // priceOracle.permit(top, tub, S("cage(uint256,uint256)"));
    }
}