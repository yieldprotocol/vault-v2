// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IContangoInsuranceFundEvents {
    event Insured(
        bytes6 indexed ilkId,
        uint128 art,
        uint128 fyTokenUsed,
        uint256 baseTokenUsed
    );
}

interface IContangoInsuranceFund is IContangoInsuranceFundEvents {
    function insure(
        bytes6 ilkId,
        uint128 art
    ) external returns (uint128 fyTokenUsed, uint256 baseTokenUsed);

    function insuranceAvailable(bytes6 ilkId) external view returns (uint256);
}
