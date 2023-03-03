// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IContangoInsuranceFundEvents {
    event Insured(
        bytes6 indexed seriesId,
        uint128 base,
        uint128 fyTokenUsed,
        uint256 baseTokenUsed
    );
}

interface IContangoInsuranceFund is IContangoInsuranceFundEvents {
    function insure(
        bytes6 seriesId,
        uint128 base
    ) external returns (uint128 fyTokenUsed, uint256 baseTokenUsed);

    function insuranceAvailable(
        bytes6 seriesId
    ) external view returns (uint256);
}
