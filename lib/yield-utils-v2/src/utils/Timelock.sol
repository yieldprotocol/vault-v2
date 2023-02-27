// SPDX-License-Identifier: MIT
// Inspired on Timelock.sol from Compound.
// Special thanks to BoringCrypto and Mudit Gupta for their feedback.
// Last audit by Trail of Bits on https://github.com/yieldprotocol/yield-utils-v2/commit/13190065ff409741d23836a33fd3d6c3059c3461

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
    function approve(bytes32 txHash) external returns (uint32);
    function cancel(bytes32 txHash) external;
    function execute(Call[] calldata functionCalls) external returns (bytes[] calldata results);
    function callWithValue(Call calldata functionCall, uint256 value) external returns (bytes memory result);
}

contract Timelock is ITimelock, AccessControl {
    using IsContract for address;

    enum STATE { UNKNOWN, PROPOSED, APPROVED }

    struct Proposal {
        STATE state;
        uint32 eta;
    }

    uint32 public constant GRACE_PERIOD = 14 days;
    uint32 public constant MINIMUM_DELAY = 1 days;
    uint32 public constant MAXIMUM_DELAY = 30 days;

    event DelaySet(uint256 indexed delay);
    event Proposed(bytes32 indexed txHash);
    event Approved(bytes32 indexed txHash, uint32 eta);
    event Cancelled(bytes32 indexed txHash);
    event Executed(bytes32 indexed txHash);

    uint32 public delay;
    mapping (bytes32 => Proposal) public proposals;

    constructor(address governor, address executor) AccessControl() {
        delay = 0; // delay is set to zero initially to allow testing and configuration. Set to a different value to go live.

        // Each role in AccessControl.sol is a 1-of-n multisig. It is recommended that trusted individual accounts get
        // `propose` and `execute` permissions, while only the governor keeps `approve` and `cancel` permissions. The
        // governor should keep the `propose` and `execute` permissions, but use them only in emergency situations
        // (such as all trusted individuals going rogue).
        _grantRole(ITimelock.propose.selector, governor);
        _grantRole(ITimelock.approve.selector, governor);
        _grantRole(ITimelock.cancel.selector, governor);
        _grantRole(ITimelock.execute.selector, governor);

        _grantRole(ITimelock.propose.selector, executor);
        _grantRole(ITimelock.execute.selector, executor);

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
        txHash = keccak256(abi.encode(functionCalls));
    }

    /// @dev Propose a transaction batch for execution
    /// @notice If several identical proposals should be simultaneously lodged, such as for example for
    /// identical monthly payments to the same contractor, their proposal hash can be made to differ by
    /// appending to each one a different view function call such as `dai.balanceOf(0xbabe)` and
    /// `dai.balanceOf(0xbeef)`.
    function propose(Call[] calldata functionCalls)
        external override auth returns (bytes32 txHash)
    {
        txHash = keccak256(abi.encode(functionCalls));
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

    /// @dev Cancel a proposal, even if it is approved
    function cancel(bytes32 txHash)
        external override auth
    {
        Proposal memory proposal = proposals[txHash];
        require(proposal.state == STATE.PROPOSED || proposal.state == STATE.APPROVED, "Not found.");

        delete proposals[txHash];
        emit Cancelled(txHash);
    }

    /// @dev Execute a proposal
    function execute(Call[] calldata functionCalls)
        external override auth returns (bytes[] memory results)
    {
        bytes32 txHash = keccak256(abi.encode(functionCalls));
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

    /// @dev To send Ether with a call, the Timelock must call itself at this function. This avoids
    /// adding a rarely used `value` in the Call struct
    function callWithValue(Call calldata functionCall, uint256 value) external override returns (bytes memory result) {
        require(msg.sender == address(this), "Only call from itself");
        bool success;
        (success, result) = functionCall.target.call{ value: value }(functionCall.data);
        if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
    }

    receive() payable external {}
}