pragma solidity ^0.8.0;


library IlksPacking {
    function select(IVat.Ilks vaultIlks, bytes1 ilkSelector) internal view returns (bytes6[6] selectedIlks) {
        uint256 count = 0;

        for (uint256 i = 0; i < vaultIlks.length; i++)
            if (ilkSelector & 2**i == 2**i)
                selectedIlks[count++] = vaultIlks[i];
        selectedIlks[5] = bytes6(count);
    }
}