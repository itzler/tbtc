pragma solidity 0.4.25;

import {SafeMath} from "../bitcoin-spv/SafeMath.sol";
import {DepositUtils} from './DepositUtils.sol';
import {BTCUtils} from "../bitcoin-spv/BTCUtils.sol";
import {BytesLib} from "../bitcoin-spv/BytesLib.sol";
import {ValidateSPV} from "../bitcoin-spv/ValidateSPV.sol";
import {IKeep} from '../interfaces/IKeep.sol';
import {DepositStates} from './DepositStates.sol';
import {OutsourceDepositLogging} from './OutsourceDepositLogging.sol';
import {CheckBitcoinSigs} from '../bitcoin-spv/SigCheck.sol';
import {TBTCConstants} from './TBTCConstants.sol';
import {IBurnableERC20} from '../interfaces/IBurnableERC20.sol';
import {CheckBitcoinSigs} from '../bitcoin-spv/SigCheck.sol';
import {DepositLiquidation} from './DepositLiquidation.sol';


library DepositRedemption {

    using SafeMath for uint256;
    using CheckBitcoinSigs for bytes;
    using BytesLib for bytes;
    using BTCUtils for bytes;
    using ValidateSPV for bytes;
    using ValidateSPV for bytes32;

    using DepositUtils for DepositUtils.Deposit;
    using DepositStates for DepositUtils.Deposit;
    using DepositLiquidation for DepositUtils.Deposit;
    using OutsourceDepositLogging for DepositUtils.Deposit;

    /// @notice     Pushes signer fee to the Keep group by transferring it to the Keep address
    /// @dev        Approves the keep contract, then expects it to call transferFrom
    function distributeSignerFee(DepositUtils.Deposit storage _d) public {
        address _tbtcAddress = _d.TBTCToken;
        IBurnableERC20 _tbtc = IBurnableERC20(_tbtcAddress);

        address _keepAddress = _d.KeepSystem;
        IKeep _keep = IKeep(_keepAddress);

        _tbtc.approve(_keepAddress, DepositUtils.signerFee());
        _keep.distributeERC20ToKeepGroup(_d.keepID, _tbtcAddress, DepositUtils.signerFee());
    }

    /// @notice         approves a digest for signing by our keep group
    /// @dev            calls out to the keep contract
    /// @param  _digest the digest to approve
    /// @return         true if approved, otherwise revert
    function approveDigest(DepositUtils.Deposit storage _d, bytes32 _digest) public returns (bool) {
        IKeep _keep = IKeep(_d.KeepSystem);
        return _keep.approveDigest(_d.keepID, _digest);
    }

    /// @notice                     Anyone can request redemption
    /// @dev                        The redeemer specifies details about the Bitcoin redemption tx
    /// @param  _d                  deposit storage pointer
    /// @param  _outputValueBytes   The 8-byte LE output size
    /// @param  _requesterPKH       The 20-byte Bitcoin pubkeyhash to which to send funds
    function requestRedemption(
        DepositUtils.Deposit storage _d,
        bytes8 _outputValueBytes,
        bytes20 _requesterPKH
    ) public {
        require(_d.inRedeemableState(), 'Redemption only available from Active or Courtesy state');

        _d.setAwaitingWithdrawalSignature();
        _d.logRedemptionRequested(
            msg.sender,
            _sighash,
            _d.utxoSize(),
            _requesterPKH,
            _requestedFee,
            _d.utxoOutpoint);

        // Burn the redeemer's TBTC plus enough extra to cover outstanding debt
        // Requires user to approve first
        /* TODO: implement such that it calls the system to burn TBTC? */
        IBurnableERC20 _tbtc = IBurnableERC20(_d.TBTCToken);
        require(_tbtc.balanceOf(msg.sender) >= _d.redemptionTBTCAmount(), 'Not enough TBTC to cover outstanding debt');
        _tbtc.burnFrom(msg.sender, TBTCConstants.getLotSize());
        _tbtc.transferFrom(msg.sender, address(this), DepositUtils.signerFee());
        _tbtc.transferFrom(msg.sender, address(this), DepositUtils.beneficiaryReward());

        // Convert the 8-byte LE ints to uint256
        uint256 _outputValue = abi.encodePacked(_outputValueBytes).reverseEndianness().bytesToUint();
        uint256 _requestedFee = _d.utxoSize().sub(_outputValue);
        require(_requestedFee >= TBTCConstants.getMinimumRedemptionFee());

        // Calculate the sighash
        bytes32 _sighash = CheckBitcoinSigs.oneInputOneOutputSighash(
            _d.utxoOutpoint,
            _d.signerPKH(),
            _d.utxoSizeBytes,
            _outputValueBytes,
            _requesterPKH);

        // write all request details
        _d.requesterAddress = msg.sender;
        _d.requesterPKH = _requesterPKH;
        _d.initialRedemptionFee = _requestedFee;
        _d.withdrawalRequestTime = block.timestamp;
        _d.lastRequestedDigest = _sighash;
        require(approveDigest(_d, _sighash));
    }

    /// @notice     Anyone may provide a withdrawal signature if it was requested
    /// @dev        The signers will be penalized if this (or provideRedemptionProof) is not called
    /// @param  _d  deposit storage pointer
    /// @param  _v  Signature recovery value
    /// @param  _r  Signature R value
    /// @param  _s  Signature S value
    function provideRedemptionSignature(
        DepositUtils.Deposit storage _d,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public {
        require(_d.inAwaitingWithdrawalSignature(), 'Not currently awaiting a signature');
        // A signature has been provided, now we wait for fee bump or redemption
        _d.setAwaitingWithdrawalProof();
        _d.logGotRedemptionSignature(
            _d.lastRequestedDigest,
            _r,
            _s);

        // If we're outside of the signature window, we COULD punish signers here
        // Instead, we consider this a no-harm-no-foul situation.
        // The signers have not stolen funds. Most likely they've just inconvenienced someone

        // The signature must be valid on the pubkey
        require(_d.signerPubkey().checkSig(
            _d.lastRequestedDigest,
            _v,
            _r,
            _s));
    }

    /// @notice                             Anyone may notify the contract that a fee bump is needed
    /// @dev                                This sends us back to AWAITING_WITHDRAWAL_SIGNATURE
    /// @param  _d                          deposit storage pointer
    /// @param  _previousOutputValueBytes   The previous output's value
    /// @param  _newOutputValueBytes        The new output's value
    /// @return                             True if successful, False if prevented by timeout, otherwise revert
    function increaseRedemptionFee(
        DepositUtils.Deposit storage _d,
        bytes8 _previousOutputValueBytes,
        bytes8 _newOutputValueBytes
    ) public returns (bool) {
        require(_d.inAwaitingWithdrawalProof());
        require(block.timestamp >= _d.withdrawalRequestTime + TBTCConstants.getIncreaseFeeTimer(), 'Fee increase not yet permitted');

        // If we should have gotten a redemption proof by now, something fishy is going on
        if (block.timestamp > _d.withdrawalRequestTime + TBTCConstants.getRedepmtionProofTimeout()) {
            _d.startSignerAbortLiquidation();
            return false;  // We return instead of reverting so that the above transition takes place
        }

        uint256 _newOutputValue = checkRelationshipToPrevious(_d, _previousOutputValueBytes, _newOutputValueBytes);

        // Calculate the next sighash
        bytes32 _sighash = CheckBitcoinSigs.oneInputOneOutputSighash(
            _d.utxoOutpoint,
            _d.signerPKH(),
            _d.utxoSizeBytes,
            _newOutputValueBytes,
            _d.requesterPKH);

        // Ratchet the signature and redemption proof timeouts
        _d.withdrawalRequestTime = block.timestamp;
        _d.lastRequestedDigest = _sighash;
        require(approveDigest(_d, _sighash));

        // Go back to waiting for a signature
        _d.setAwaitingWithdrawalSignature();
        _d.logRedemptionRequested(
            msg.sender,
            _sighash,
            _d.utxoSize(),
            _d.requesterPKH,
            _d.utxoSize().sub(_newOutputValue),
            _d.utxoOutpoint);
    }

    function checkRelationshipToPrevious(
        DepositUtils.Deposit storage _d,
        bytes8 _previousOutputValueBytes,
        bytes8 _newOutputValueBytes
    ) public view returns (uint256 _newOutputValue){

        // Check that we're incrementing the fee by exactly the requester's initial fee
        uint256 _previousOutputValue = DepositUtils.bytes8LEToUint(_previousOutputValueBytes);
        _newOutputValue = DepositUtils.bytes8LEToUint(_newOutputValueBytes);
        require(_previousOutputValue.sub(_newOutputValue) == _d.initialRedemptionFee, 'Not an allowed fee step');

        // Calculate the previous one so we can check that it really is the previous one
        bytes32 _previousSighash = CheckBitcoinSigs.oneInputOneOutputSighash(
            _d.utxoOutpoint,
            _d.signerPKH(),
            _d.utxoSizeBytes,
            _previousOutputValueBytes,
            _d.requesterPKH);
        require(_d.wasDigestApprovedForSigning(_previousSighash) == _d.withdrawalRequestTime, 'Provided previous value does not yield previous sighash');
    }

    /// @notice                 Anyone may provide a withdrawal proof to prove redemption
    /// @dev                    The signers will be penalized if this is not called
    /// @param  _d              deposit storage pointer
    /// @param  _bitcoinTx      The bitcoin tx that purportedly contain the redemption output
    /// @param  _merkleProof    The merkle proof of inclusion of the tx in the bitcoin block
    /// @param  _index          The index of the tx in the Bitcoin block (1-indexed)
    /// @param  _bitcoinHeaders An array of tightly-packed bitcoin headers
    function provideRedemptionProof(
        DepositUtils.Deposit storage _d,
        bytes _bitcoinTx,
        bytes _merkleProof,
        uint256 _index,
        bytes _bitcoinHeaders
    ) public {
        bytes32 _txid;
        uint256 _fundingOutputValue;

        require(_d.inRedemption(), 'Redemption proof only allowed from redemption flow');
        (_txid, _fundingOutputValue) = redemptionTransactionChecks(_d, _bitcoinTx);
        // We don't use checkproof here because we need access to the parse info
        require(_txid != bytes32(0), 'Failed tx parsing');
        require(
            _txid.prove(
                _bitcoinHeaders.extractMerkleRootLE().toBytes32(),
                _merkleProof,
                _index),
            'Tx merkle proof is not valid for provided header');
        _d.evaluateProofDifficulty(_bitcoinHeaders);

        /* TODO: refactor redemption flow to improve this */
        require((_d.utxoSize().sub(_fundingOutputValue)) <= _d.initialRedemptionFee * 5, 'Fee unexpectedly very high');

        // Transfer TBTC to signers
        distributeSignerFee(_d);

        // Transfer withheld amount to beneficiary
        _d.distributeBeneficiaryReward();

        // We're done yey!
        _d.setRedeemed();
        _d.redemptionTeardown();
        _d.logRedeemed(_txid);
    }

    function redemptionTransactionChecks(
        DepositUtils.Deposit storage _d,
        bytes _bitcoinTx
    ) public view returns (bytes32, uint256) {
        bytes memory _nIns;
        bytes memory _ins;
        bytes memory _nOuts;
        bytes memory _outs;
        bytes memory _locktime;
        bytes32 _txid;
        (_nIns, _ins, _nOuts, _outs, _locktime, _txid) = _bitcoinTx.parseTransaction();
        require(keccak256(_locktime) == keccak256(hex'00000000'), 'Wrong locktime set');
        require(keccak256(_nIns) == keccak256(hex'01'), 'Too many ins');
        require(keccak256(_nOuts) == keccak256(hex'01'), 'Too many outs');
        require(keccak256(_ins.extractOutpoint()) == keccak256(_d.utxoOutpoint),
                'Tx spends the wrong UTXO');
        require(keccak256(_outs.extractHash()) == keccak256(abi.encodePacked(_d.requesterPKH)),
                'Tx sends value to wrong pubkeyhash');
        return( _txid, uint256(_outs.extractValue()));
    }



    /// @notice     Anyone may notify the contract that the signers have failed to produce a signature
    /// @dev        This is considered fraud, and is punished
    /// @param  _d  deposit storage pointer
    function notifySignatureTimeout(DepositUtils.Deposit storage _d) public {
        require(_d.inAwaitingWithdrawalSignature());
        require(block.timestamp > _d.withdrawalRequestTime + TBTCConstants.getSignatureTimeout());
        _d.startSignerAbortLiquidation();  // not fraud, just failure
    }

    /// @notice     Anyone may notify the contract that the signers have failed to produce a redemption proof
    /// @dev        This is considered fraud, and is punished
    /// @param  _d  deposit storage pointer
    function notifyRedemptionProofTimeout(DepositUtils.Deposit storage _d) public {
        require(_d.inAwaitingWithdrawalProof());
        require(block.timestamp > _d.withdrawalRequestTime + TBTCConstants.getRedepmtionProofTimeout());
        _d.startSignerAbortLiquidation();  // not fraud, just failure
    }
}