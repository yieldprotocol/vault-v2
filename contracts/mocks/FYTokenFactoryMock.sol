// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "@yield-protocol/vault-interfaces/src/IOracle.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/vault-interfaces/src/IFYTokenFactory.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../FYToken.sol";


/// @dev The FYTokenFactory creates new FYToken instances.
contract FYTokenFactoryMock is IFYTokenFactory, AccessControl {

  /// @dev Deploys a new fyToken.
  /// @return fyToken The fyToken address.
  function createFYToken(
    bytes6 baseId,
    IOracle oracle,
    IJoin baseJoin,
    uint32 maturity,
    string calldata name,
    string calldata symbol
  )
    external override
    auth
    returns (address)
  {
    FYToken fyToken = new FYToken(
      baseId,
      oracle,
      baseJoin,
      maturity,
      name,     // Derive from base and maturity, perhaps
      symbol    // Derive from base and maturity, perhaps
    );

    fyToken.grantRole(ROOT, msg.sender);
    fyToken.renounceRole(ROOT, address(this));

    emit FYTokenCreated(address(fyToken), baseJoin.asset(), maturity);

    return address(fyToken);
  }
} 