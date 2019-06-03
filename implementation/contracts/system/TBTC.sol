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

        // Price Oracle
        // ------------
        priceOracle.setAuthority(authority)
        priceOracle.setOwner(this)

        // Option 1. Using DSGuard
        address priceOracleOperator;
        priceOracle.permit(priceOracleOperator, priceOracle, S("updatePrice(uint128)"));

        // Option 2. Using DSGuard
        uint8 PRICE_ORACLE_OPERATOR_ROLE = 0;        
        priceOracle.permit(PRICE_ORACLE_OPERATOR_ROLE, priceOracle, S("updatePrice(uint128)"));
    }
}