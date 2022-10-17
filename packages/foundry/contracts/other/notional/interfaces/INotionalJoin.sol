// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../../../interfaces/IJoin.sol";

interface INotionalJoin is IJoin {
    function underlying() external view returns(address);
    function underlyingJoin() external view returns(address);
    function maturity() external view returns(uint40); // Maturity date for fCash
    function currencyId() external view returns(uint16); // Notional currency id for the underlying
    function fCashId() external view returns(uint256); // This ERC1155 Join only accepts one fCashId from the ERC1155 token
}
