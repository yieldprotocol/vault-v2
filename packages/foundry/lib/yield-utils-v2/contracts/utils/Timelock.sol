// SPDX-License-Identifier: MIT
// Inspired on Timelock.sol from Compound.
// Special thanks to BoringCrypto and Mudit Gupta for their feedback.

pragma solidity ^0.8.0;
import "../access/AccessControl.sol";
import "./RevertMsgExtractor.sol";
import "./IsContract.sol";


interface ITimelock {
    struct Call {
        address target;
        bytes data;
    }

    function setDelay(uint32 delay_) external;
    function propose(Call[] calldata functionCalls) external returns (bytes32 txHash);
    function proposeRepeated(Call[] calldata functionCalls, uint256 salt) external returns (bytes32 txHash);
    function approve(bytes32 txHash) external returns (uint32);
    function execute(Call[] calldata functionCalls) external returns (bytes[] calldata results);
    function executeRepeated(Call[] calldata functionCalls, uint256 salt) external returns (bytes[] calldata results);
}

contract Timelock is ITimelock, AccessControl {
    using IsContract for address;

    enum STATE { UNKNOWN, PROPOSED, APPROVED }

    struct Proposal {
        STATE state;
        uint32 eta;
    }

    uint32 public constant GRACE_PERIOD = 14 days;
    uint32 public constant MINIMUM_DELAY = 2 days;
    uint32 public constant MAXIMUM_DELAY = 30 days;

    event DelaySet(uint256 indexed delay);
    event Proposed(bytes32 indexed txHash);
    event Approved(bytes32 indexed txHash, uint32 eta);
    event Executed(bytes32 indexed txHash);

    uint32 public delay;
    mapping (bytes32 => Proposal) public proposals;

    constructor(address governor, address executor) AccessControl() {
        delay = 0; // delay is set to zero initially to allow testing and configuration. Set to a different value to go live.

        // Each role in AccessControl.sol is a 1-of-n multisig. It is recommended that trusted individual accounts get `propose`
        // and `execute` permissions, while only the governor keeps `approve` permissions. The governor should keep the `propose`
        // and `execute` permissions, but use them only in emergency situations (such as all trusted individuals going rogue).
        _grantRole(ITimelock.propose.selector, governor);
        _grantRole(ITimelock.proposeRepeated.selector, governor);
        _grantRole(ITimelock.approve.selector, governor);
        _grantRole(ITimelock.execute.selector, governor);
        _grantRole(ITimelock.executeRepeated.selector, governor);

        _grantRole(ITimelock.propose.selector, executor);
        _grantRole(ITimelock.proposeRepeated.selector, executor);
        _grantRole(ITimelock.execute.selector, executor);
        _grantRole(ITimelock.executeRepeated.selector, executor);

        // Changing the delay must now be executed through this Timelock contract
        _grantRole(ITimelock.setDelay.selector, address(this)); // bytes4(keccak256("setDelay(uint256)"))

        // Granting roles (propose, approve, execute, setDelay) must now be executed through this Timelock contract
        _grantRole(ROOT, address(this));
        _revokeRole(ROOT, msg.sender);
    }

    /// @dev Change the delay for approved proposals
    function setDelay(uint32 delay_) external override auth {
        require(delay_ >= MINIMUM_DELAY, "Must exceed minimum delay.");
        require(delay_ <= MAXIMUM_DELAY, "Must not exceed maximum delay.");
        delay = delay_;

        emit DelaySet(delay_);
    }

    /// @dev Compute the hash for a proposal
    function hash(Call[] calldata functionCalls)
        external pure returns (bytes32 txHash)
    {
        return _hash(functionCalls, 0);
    }

    /// @dev Compute the hash for a proposal, with other identical proposals existing
    /// @param salt Unique identifier for the transaction when repeatedly proposed. Chosen by governor.
    function hashRepeated(Call[] calldata functionCalls, uint256 salt)
        external pure returns (bytes32 txHash)
    {
        return _hash(functionCalls, salt);
    }

    /// @dev Compute the hash for a proposal
    function _hash(Call[] calldata functionCalls, uint256 salt)
        private pure returns (bytes32 txHash)
    {
        txHash = keccak256(abi.encode(functionCalls, salt));
    }

    /// @dev Propose a transaction batch for execution
    function propose(Call[] calldata functionCalls)
        external override auth returns (bytes32 txHash)
    {
        return _propose(functionCalls, 0);
    }

    /// @dev Propose a transaction batch for execution, with other identical proposals existing
    /// @param salt Unique identifier for the transaction when repeatedly proposed. Chosen by governor.
    function proposeRepeated(Call[] calldata functionCalls, uint256 salt)
        external override auth returns (bytes32 txHash)
    {
        return _propose(functionCalls, salt);
    }

    /// @dev Propose a transaction batch for execution
    function _propose(Call[] calldata functionCalls, uint256 salt)
        private returns (bytes32 txHash)
    {
        txHash = keccak256(abi.encode(functionCalls, salt));
        require(proposals[txHash].state == STATE.UNKNOWN, "Already proposed.");
        proposals[txHash].state = STATE.PROPOSED;
        emit Proposed(txHash);
    }

    /// @dev Approve a proposal and set its eta
    function approve(bytes32 txHash)
        external override auth returns (uint32 eta)
    {
        Proposal memory proposal = proposals[txHash];
        require(proposal.state == STATE.PROPOSED, "Not proposed.");
        eta = uint32(block.timestamp) + delay;
        proposal.state = STATE.APPROVED;
        proposal.eta = eta;
        proposals[txHash] = proposal;
        emit Approved(txHash, eta);
    }

    /// @dev Execute a proposal
    function execute(Call[] calldata functionCalls)
        external override auth returns (bytes[] memory results)
    {
        return _execute(functionCalls, 0);
    }
    
    /// @dev Execute a proposal, among several identical ones
    /// @param salt Unique identifier for the transaction when repeatedly proposed. Chosen by governor.
    function executeRepeated(Call[] calldata functionCalls, uint256 salt)
        external override auth returns (bytes[] memory results)
    {
        return _execute(functionCalls, salt);
    }

    /// @dev Execute a proposal
    function _execute(Call[] calldata functionCalls, uint256 salt)
        private returns (bytes[] memory results)
    {
        bytes32 txHash = keccak256(abi.encode(functionCalls, salt));
        Proposal memory proposal = proposals[txHash];

        require(proposal.state == STATE.APPROVED, "Not approved.");
        require(uint32(block.timestamp) >= proposal.eta, "ETA not reached.");
        require(uint32(block.timestamp) <= proposal.eta + GRACE_PERIOD, "Proposal is stale.");

        delete proposals[txHash];

        results = new bytes[](functionCalls.length);
        for (uint256 i = 0; i < functionCalls.length; i++){
            require(functionCalls[i].target.isContract(), "Call to a non-contract");
            (bool success, bytes memory result) = functionCalls[i].target.call(functionCalls[i].data);
            if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
            results[i] = result;
        }
        emit Executed(txHash);
    }
}