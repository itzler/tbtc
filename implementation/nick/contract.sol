pragma solidity ^0.5.6;

contract Contract {
    bytes arr;
    
    constructor() public {}
    
    function returnBytes() external view returns (bytes memory) {
        return arr;
    }
}