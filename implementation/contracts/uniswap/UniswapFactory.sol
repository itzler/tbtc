pragma solidity 0.4.25;

/*
seth-rpc: error:   message    VM Exception while processing transaction: revert
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xEbB5080266d96aC87bE5ccd5F9Acfc7cF93Eeec3 "exchange()(address)"   
afbf67ffcaeeacd0936e99ddbaeba603637caf98
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xB73863A2230866F2660A11D4B6557972eAc291F6 "getToken(address)" 0x726a0F71BCa1Cd6Ab78521e137A3dD0054710395   
0x0000000000000000000000000000000000000000000000000000000000000000
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xB73863A2230866F2660A11D4B6557972eAc291F6 "getExchange(address)(address)" 0x726a0F71BCa1Cd6Ab78521e137A3dD0054710395
0000000000000000000000000000000000000000
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xB73863A2230866F2660A11D4B6557972eAc291F6 "getExchange(address)(address)" 0x726a0F71BCa1Cd6Ab78521e137A3dD0054710395
0000000000000000000000000000000000000000
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xB73863A2230866F2660A11D4B6557972eAc291F6 "getExchange(address)(address)" 726a0F71BCa1Cd6Ab78521e137A3dD0054710395 
0000000000000000000000000000000000000000
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call afbf67ffcaeeacd0936e99ddbaeba603637caf98 "getExchange(address)(address)" 0x726a0F71BCa1Cd6Ab78521e137A3dD0054710395 
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xEbB5080266d96aC87bE5ccd5F9Acfc7cF93Eeec3 "factory()(address)"599759eb894a5c2f87949284a9d3b64e233c179e
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xB73863A2230866F2660A11D4B6557972eAc291F6 "implementation()(address)"     599759eb894a5c2f87949284a9d3b64e233c179e
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 599759eb894a5c2f87949284a9d3b64e233c179e "getExchange(address)(address)" 726a0F71BCa1Cd6Ab78521e137A3dD0054710395
a8b49efb568daab7bf5db2b05177bcf48b3ae588
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xB73863A2230866F2660A11D4B6557972eAc291F6 "getExchange(address)(address)" 726a0F71BCa1Cd6Ab78521e137A3dD0054710395
0000000000000000000000000000000000000000
(base) ➜  implementation git:(onchain-liquidation) ✗ seth call 0xB73863A2230866F2660A11D4B6557972eAc291F6 "getExchange(address)(address)" 726a0F71BCa1Cd6Ab78521e137A3dD0054710395
*/

contract UniswapFactory {
    bytes32 private constant implementationPosition = keccak256("proxy.implementation");

    constructor(address _implementation) public {
        require(_implementation != address(0), "Implementation address can't be zero.");
        setImplementation(_implementation);
    }

    /**
     * @dev Gets the address of the current implementation.
     * @return address of the current implementation.
    */
    function implementation() public view returns (address _implementation) {
        bytes32 position = implementationPosition;
        /* solium-disable-next-line */
        assembly {
            _implementation := sload(position)
        }
    }

    /**
     * @dev Sets the address of the current implementation.
     * @param _implementation address representing the new implementation to be set.
    */
    function setImplementation(address _implementation) internal {
        bytes32 position = implementationPosition;
        /* solium-disable-next-line */
        assembly {
            sstore(position, _implementation)
        }
    }

    /**
     * @dev Delegate call to the current implementation contract.
     */
    function() external payable {
        address _impl = implementation();
        /* solium-disable-next-line */
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize)
            let result := delegatecall(gas, _impl, ptr, calldatasize, 0, 0)
            let size := returndatasize
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }
}