pragma solidity 0.4.25;

import {ITBTCSystem} from '../../interfaces/ITBTCSystem.sol';
import {IERC721} from '../../interfaces/IERC721.sol';
import {DepositLog} from '../../DepositLog.sol';
import {IUniswapFactory} from "../../uniswap/IUniswapFactory.sol";
import {TBTC} from "../../tokens/TBTC.sol";

contract SystemStub is ITBTCSystem, IERC721, DepositLog {

    uint256 current = 1;
    uint256 past = 1;
    uint256 oraclePrice = 10 ** 12;

    IUniswapFactory uniswapFactory;
    TBTC tbtc;

    function setExternalAddresses(
        address _uniswapFactory,
        address _tbtc
    ) external {
        uniswapFactory = IUniswapFactory(_uniswapFactory);
        tbtc = TBTC(_tbtc);
    }

    function getTBTCUniswapExchange() external view returns (address) {
        return uniswapFactory.getExchange(address(tbtc));
    }

    function setOraclePrice(uint256 _oraclePrice) external {oraclePrice = _oraclePrice;}
    function setCurrentDiff(uint256 _current) external {current = _current;}
    function setPreviousDiff(uint256 _past) external {past = _past;}

    // override parent
    function approvedToLog(address _caller) public view returns (bool) {_caller; return true;}

    // TBTCSystem
    function fetchOraclePrice() external view returns (uint256) {return oraclePrice;}
    function fetchRelayCurrentDifficulty() external view returns (uint256) {return current;}
    function fetchRelayPreviousDifficulty() external view returns (uint256) {return past;}

    // 721
    function balanceOf(address owner) public view returns (uint256 balance) {owner; balance = 0;}
    function ownerOf(uint256 tokenId) public view returns (address owner) {tokenId; owner = address(0);}
    function approve(address to, uint256 tokenId) public {to; tokenId;}
    function getApproved(uint256 tokenId) public view returns (address operator) {tokenId; operator = address(8);}
    function setApprovalForAll(address operator, bool _approved) public {operator; _approved;}
    function isApprovedForAll(address owner, address operator) public view returns (bool) {owner; operator;}
    function transferFrom(address from, address to, uint256 tokenId) public {from; to; tokenId;}
    function safeTransferFrom(address from, address to, uint256 tokenId) public {from; to; tokenId;}
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {from; to; tokenId; data;}
}