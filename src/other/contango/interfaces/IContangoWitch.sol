// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IContangoInsuranceFund.sol";

interface IContangoWitchEvents {
    event InsuranceLineSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        uint32 duration,
        uint64 maxInsuredProportion,
        IContangoInsuranceFund insuranceFund,
        uint64 insurancePremium,
        address insurancePremiumReceiver
    );
    event InsuranceLineStatusSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        bool disabled
    );
    event DefaultInsurancePremiumSet(uint64 defaultInsurancePremium);
    event LiquidationInsured(
        bytes12 indexed vaultId,
        uint256 artInsured,
        uint256 baseInsured
    );
    event AuctionStartedCallbackFailed(
        address indexed owner,
        bytes12 indexed vaultId
    );
    event CollateralBoughtCallbackFailed(
        address indexed owner,
        bytes12 indexed vaultId,
        uint256 ink,
        uint256 art
    );
    event AuctionEndedCallbackFailed(
        address indexed owner,
        bytes12 indexed vaultId
    );
}

interface IContangoWitch is IContangoWitchEvents {
    function setInsuranceLine(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 maxInsuredProportion,
        IContangoInsuranceFund insuranceFund,
        uint64 insurancePremium,
        address insurancePremiumReceiver
    ) external;

    function setInsuranceLineStatus(
        bytes6 ilkId,
        bytes6 baseId,
        bool enabled
    ) external;

    function setDefaultInsurancePremium(
        uint64 defaultInsurancePremium_
    ) external;
}
