pragma solidity ^0.8.0;
import "../libraries/DataTypes.sol";


library IlksPacking {
    function indexes(bytes1 ilkSelector) internal view returns (uint256[] memory selectedIlks) {
        for (uint256 i = 0; i < 5; i++)
            if (ilkSelector & 2**i == 2**i)
                selectedIlks.push(i);
    }

    function identifiers(bytes1 ilkSelector, DataTypes.Ilks memory ilks) internal view returns (bytes6[] memory selectedIlks) {
        for (uint256 i = 0; i < 5; i++)
            if (ilkSelector & 2**i == 2**i)
                selectedIlks.push(ilks.ids[i]);
    }
}