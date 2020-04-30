const Vat= artifacts.require('./Vat');
const MockTreasury = artifacts.require('./MockTreasury');
const MockContract = artifacts.require("./MockContract")
const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const ERC20 = artifacts.require("./ERC20");

contract('Treasury', async (accounts) =>  {
    let VatI;
    let owner = accounts[0];

    beforeEach('setup and deploy OracleMock', async() => {
        VatI = await Vat.new();
    });

    describe("post()", () => {

        it("should fail if not authorized", async() => {

        });
    });
});