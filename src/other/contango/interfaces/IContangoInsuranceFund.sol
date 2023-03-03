// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IContangoInsuranceFundEvents {
    event Insured(
        bytes6 indexed ilkId,
        uint128 art,
        uint128 fyTokens,
        uint128 baseTokens
    );
}

interface IContangoInsuranceFund is IContangoInsuranceFundEvents {
    function insure(
        bytes6 ilkId,
        uint128 art
    ) external returns (uint128 fyTokens, uint128 baseTokens);
}
