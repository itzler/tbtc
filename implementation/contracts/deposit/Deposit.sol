pragma solidity 0.4.25;

import {DepositLiquidation} from './DepositLiquidation.sol';
import {DepositUtils} from './DepositUtils.sol';
import {DepositFunding} from './DepositFunding.sol';
import {DepositRedemption} from './DepositRedemption.sol';

contract Deposit {

    using DepositRedemption for DepositUtils.Deposit;
    using DepositFunding for DepositUtils.Deposit;
    using DepositLiquidation for DepositUtils.Deposit;
    using DepositUtils for DepositUtils.Deposit;

    DepositUtils.Deposit self;

    // We separate the constructor from createNewDeposit to make proxy factories easier
    constructor () public {}

    function () public payable {}

    // THIS IS THE INIT FUNCTION
    /// @notice         The system can spin up a new deposit
    /// @dev            This should be called by an approved contract, not a developer
    /// @param _m       m for m-of-n
    /// @param _m       n for m-of-n
    /// @return         True if successful, otherwise revert
    function createNewDeposit(
        address _TBTCSystem,
        address _TBTCToken,
        address _KeepSystem,
        uint256 _m,
        uint256 _n
    ) payable public returns (bool) {
        self.TBTCSystem = _TBTCSystem;
        self.TBTCToken = _TBTCToken;
        self.KeepSystem = _KeepSystem;
        self.createNewDeposit(_m, _n);
        return true;
    }

    /// @notice     Get the integer representing the current state
    /// @dev        We implement this because contracts don't handle foreign enums well
    /// @return     The 0-indexed state from the DepositStates enum
    function getCurrentState() public view returns (uint256) {
        return uint256(self.currentState);
    }

    /// @notice                     Anyone can request redemption
    /// @dev                        The redeemer specifies details about the Bitcoin redemption tx
    /// @param  _outputValueBytes   The 8-byte LE output size
    /// @param  _requesterPKH       The 20-byte Bitcoin pubkeyhash to which to send funds
    /// @return                     True if successful, otherwise revert
    function requestRedemption(
        bytes8 _outputValueBytes,
        bytes20 _requesterPKH
    ) public returns (bool) {
        self.requestRedemption(_outputValueBytes, _requesterPKH);
        return true;
    }

    /// @notice     Anyone may provide a withdrawal signature if it was requested
    /// @dev        The signers will be penalized if this (or provideRedemptionProof) is not called
    /// @param  _v  Signature recovery value
    /// @param  _r  Signature R value
    /// @param  _s  Signature S value
    /// @return     True if successful, False if prevented by timeout, otherwise revert
    function provideRedemptionSignature(
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public returns (bool) {
        self.provideRedemptionSignature(_v, _r, _s);
        return true;
    }

    /// @notice                             Anyone may notify the contract that a fee bump is needed
    /// @dev                                This sends us back to AWAITING_WITHDRAWAL_SIGNATURE
    /// @param  _previousOutputValueBytes   The previous output's value
    /// @param  _newOutputValueBytes        The new output's value
    /// @return                             True if successful, False if prevented by timeout, otherwise revert
    function increaseRedemptionFee(
        bytes8 _previousOutputValueBytes,
        bytes8 _newOutputValueBytes
    ) public returns (bool) {
        return self.increaseRedemptionFee(_previousOutputValueBytes, _newOutputValueBytes);
    }

    /// @notice                 Anyone may provide a withdrawal proof to prove redemption
    /// @dev                    The signers will be penalized if this is not called
    /// @param  _bitcoinTx      The bitcoin tx that purportedly contain the redemption output
    /// @param  _merkleProof    The merkle proof of inclusion of the tx in the bitcoin block
    /// @param  _index          The index of the tx in the Bitcoin block (1-indexed)
    /// @param  _bitcoinHeaders An array of tightly-packed bitcoin headers
    /// @return                 True if successful, otherwise revert
    function provideRedemptionProof(
        bytes _bitcoinTx,
        bytes _merkleProof,
        uint256 _index,
        bytes _bitcoinHeaders
    ) public returns (bool) {
        self.provideRedemptionProof(_bitcoinTx, _merkleProof, _index, _bitcoinHeaders);
        return true;
    }

    /// @notice     Anyone may notify the contract that the signers have failed to produce a signature
    /// @dev        This is considered fraud, and is punished
    /// @return     True if successful, otherwise revert
    function notifySignatureTimeout() public returns (bool) {
        self.notifySignatureTimeout();
        return true;
    }

    /// @notice     Anyone may notify the contract that the signers have failed to produce a redemption proof
    /// @dev        This is considered fraud, and is punished
    /// @return     True if successful, otherwise revert
    function notifyRedemptionProofTimeout() public returns (bool) {
        self.notifyRedemptionProofTimeout();
        return true;
    }





    //
    // FUNDING FLOW
    //

    /// @notice     Anyone may notify the contract that signing group setup has timed out
    /// @dev        We rely on the keep system punishes the signers in this case
    /// @return     True if successful, otherwise revert
    function notifySignerSetupFailure() public returns (bool) {
        self.notifySignerSetupFailure();
        return true;
    }

    /// @notice             we poll the Keep contract to retrieve our pubkey
    /// @dev                We store the pubkey as 2 bytestrings, X and Y.
    /// @return             True if successful, otherwise revert
    function retrieveSignerPubkey() public returns (bool) {
        self.retrieveSignerPubkey();
        return true;
    }

    /// @notice     Anyone may notify the contract that the funder has failed to send BTC
    /// @dev        This is considered a funder fault, and we revoke their bond
    /// @return     True if successful, otherwise revert
    function notifyFundingTimeout() public returns (bool) {
        self.notifyFundingTimeout();
        return true;
    }

    /// @notice                 Anyone can provide a signature that was not requested to prove fraud during funding
    /// @dev                    ECDSA is NOT SECURE unless you verify the digest
    /// @param  _v              Signature recovery value
    /// @param  _r              Signature R value
    /// @param  _s              Signature S value
    /// @param _signedDigest    The digest signed by the signature vrs tuple
    /// @param _preimage        The sha256 preimage of the digest
    /// @return                 True if successful, otherwise revert
    function provideFundingECDSAFraudProof(
        uint8 _v,
        bytes32 _r,
        bytes32 _s,
        bytes32 _signedDigest,
        bytes _preimage
    ) public returns (bool) {
        self.provideFundingECDSAFraudProof(_v, _r, _s, _signedDigest, _preimage);
        return true;
    }

    /// @notice     Anyone may notify the contract no funding proof was submitted during funding fraud
    /// @dev        This is not a funder fault. The signers have faulted, so the funder shouldn't fund
    /// @return     True if successful, otherwise revert
    function notifyFraudFundingTimeout() public returns (bool) {
        self.notifyFraudFundingTimeout();
        return true;
    }

    /// @notice                 Anyone may notify the deposit of a funding proof during funding fraud
    /// @dev                    We reward the funder the entire bond if this occurs
    /// @param  _bitcoinTx      The bitcoin tx that purportedly contains the funding output
    /// @param  _merkleProof    The merkle proof of inclusion of the tx in the bitcoin block
    /// @param  _index          The index of the tx in the Bitcoin block (1-indexed)
    /// @param  _bitcoinHeaders An array of tightly-packed bitcoin headers
    /// @return                 True if successful, False if prevented by timeout, otherwise revert
    function provideFraudBTCFundingProof(
        bytes _bitcoinTx,
        bytes _merkleProof,
        uint256 _index,
        bytes _bitcoinHeaders
    ) public returns (bool) {
        self.provideFraudBTCFundingProof(_bitcoinTx, _merkleProof, _index, _bitcoinHeaders);
        return true;
    }

    /// @notice                 Anyone may notify the deposit of a funding proof to activate the deposit
    /// @dev                    This is the happy-path of the funding flow. It means that we have suecceeded
    /// @param  _bitcoinTx      The bitcoin tx that purportedly contains the funding output
    /// @param  _merkleProof    The merkle proof of inclusion of the tx in the bitcoin block
    /// @param  _index          The index of the tx in the Bitcoin block (1-indexed)
    /// @param  _bitcoinHeaders An array of tightly-packed bitcoin headers
    /// @return                 True if successful, False if prevented by timeout, otherwise revert
    function provideBTCFundingProof(
        bytes _bitcoinTx,
        bytes _merkleProof,
        uint256 _index,
        bytes _bitcoinHeaders
    ) public returns (bool) {
        self.provideBTCFundingProof(_bitcoinTx, _merkleProof, _index, _bitcoinHeaders);
        return true;
    }

    //
    // FRAUD
    //

    /// @notice                 Anyone can provide a signature that was not requested to prove fraud
    /// @dev                    ECDSA is NOT SECURE unless you verify the digest
    /// @param  _v              Signature recovery value
    /// @param  _r              Signature R value
    /// @param  _s              Signature S value
    /// @param _signedDigest    The digest signed by the signature vrs tuple
    /// @param _preimage        The sha256 preimage of the digest
    /// @return                 True if successful, otherwise revert
    function provideECDSAFraudProof(
        uint8 _v,
        bytes32 _r,
        bytes32 _s,
        bytes32 _signedDigest,
        bytes _preimage
    ) public returns (bool) {
        self.provideECDSAFraudProof(_v, _r, _s, _signedDigest, _preimage);
        return true;
    }

    /// @notice                 Anyone may notify the deposit of fraud via an SPV proof
    /// @dev                    We strong prefer ECDSA fraud proofs
    /// @param  _bitcoinTx      The bitcoin tx that purportedly contains the funding output
    /// @param  _merkleProof    The merkle proof of inclusion of the tx in the bitcoin block
    /// @param  _index          The index of the tx in the Bitcoin block (1-indexed)
    /// @param  _bitcoinHeaders An array of tightly-packed bitcoin headers
    /// @return                 True if successful, otherwise revert
    function provideSPVFraudProof(
        bytes _bitcoinTx,
        bytes _merkleProof,
        uint256 _index,
        bytes _bitcoinHeaders
    ) public returns (bool) {
        self.provideSPVFraudProof(_bitcoinTx, _merkleProof, _index, _bitcoinHeaders);
        return true;
    }

    ///
    /// LIQUIDATION
    ///

    /// @notice     Closes an auction and purchases the signer bonds. Payout to buyer, funder, then signers if not fraud
    /// @dev        For interface, reading auctionValue will give a past value. the current is better
    /// @return     True if successful, revert otherwise
    function purchaseSignerBondsAtAuction() public returns (bool) {
        self.purchaseSignerBondsAtAuction();
        return true;
    }

    /// @notice     Notify the contract that the signers are undercollateralized
    /// @dev        Calls out to the system for oracle info
    /// @return     True if successful, otherwise revert
    function notifyCourtesyCall() public returns (bool) {
        self.notifyCourtesyCall();
        return true;
    }

    /// @notice     Goes from courtesy call to active
    /// @dev        Only callable if collateral is sufficient and the deposit is not expiring
    /// @return     True if successful, otherwise revert
    function exitCourtesyCall() public returns (bool) {
        self.exitCourtesyCall();
        return true;
    }

    /// @notice     Notify the contract that the signers are undercollateralized
    /// @dev        Calls out to the system for oracle info
    /// @return     True if successful, otherwise revert
    function notifyUndercollateralizedLiquidation() public returns (bool) {
        self.notifyUndercollateralizedLiquidation();
        return true;
    }

    /// @notice     Notifies the contract that the courtesy period has elapsed
    /// @dev        This is treated as an abort, rather than fraud
    /// @return     True if successful, otherwise revert
    function notifyCourtesyTimeout() public returns (bool) {
        self.notifyCourtesyTimeout();
        return true;
    }

    /// @notice     Notifies the contract that its term limit has been reached
    /// @dev        This initiates a courtesy call
    /// @return     True if successful, otherwise revert
    function notifyDepositExpiryCourtesyCall() public returns (bool) {
        self.notifyDepositExpiryCourtesyCall();
        return true;
    }
}