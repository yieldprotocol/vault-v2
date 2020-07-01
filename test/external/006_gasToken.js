const GasToken1 = artifacts.require('GasToken1');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('GasToken1', async (accounts) =>  {
    let [ owner ] = accounts;
    let gasToken;

    const storedTokens = 10;

    beforeEach(async() => {
        gasToken = await GasToken1.new();
    });

    it("allows to mint gasTokens", async() => {
        await gasToken.mint(storedTokens, { from: owner });

        assert.equal(
            await gasToken.balanceOf(owner),   
            storedTokens.toString(),
            "Owner should have gas tokens",
        );
    });

    describe("with gas tokens", () => {
        beforeEach(async() => {
            await gasToken.mint(storedTokens, { from: owner });
        });

        it("allows to free gasTokens", async() => {
            await gasToken.free(storedTokens, { from: owner });

            assert.equal(
                await gasToken.balanceOf(owner),   
                0,
                "Owner should have no gas tokens",
            );
        });
    });
});