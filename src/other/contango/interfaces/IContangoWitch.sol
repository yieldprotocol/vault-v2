// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IContangoWitchEvents {
    event InsuranceLineSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        uint32 duration,
        uint64 maxInsuredProportion,
        uint64 insurancePremium
    );
    event InsuranceLineStatusSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        bool disabled
    );
    event DefaultInsurancePremiumSet(uint64 defaultInsurancePremium);
    event InsuranceFundSet(address indexed insuranceFund);
    event LiquidationInsured(
        bytes12 indexed vaultId,
        uint256 artInsured,
        uint256 baseInsured
    );
}

interface IContangoWitch is IContangoWitchEvents {
    function setInsuranceLine(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 maxInsuredProportion,
        uint64 insurancePremium
    ) external;

    function setInsuranceLineStatus(
        bytes6 ilkId,
        bytes6 baseId,
        bool enabled
    ) external;

    function setDefaultInsurancePremium(
        uint64 defaultInsurancePremium_
    ) external;

    function setInsuranceFund(address insuranceFund_) external;
}
