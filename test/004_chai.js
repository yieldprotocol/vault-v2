const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('./Chai');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad } = require('./shared/utils');

contract('Chai', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let chai;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const limits =  10000;
    const spot  = 1.5;
    const rate  = 1.25;
    const daiDebt = 96;    // Dai debt for `frob`: 100
    const daiTokens = daiDebt * rate;
    const wethTokens = daiDebt * rate / spot;
    const chi = 1.2;
    const chaiTokens = daiTokens / chi;

    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, toRay(spot), { from: owner });
        await vat.file(ilk, linel, toRad(limits), { from: owner });
        await vat.file(Line, toRad(limits)); // TODO: Why can't we specify `, { from: owner }`?
        await vat.fold(ilk, vat.address, toRay(rate - 1), { from: owner }); // 1 + 0.25

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );

        // Borrow some dai
        await weth.deposit({ from: owner, value: toWad(wethTokens)});
        await weth.approve(wethJoin.address, toWad(wethTokens), { from: owner }); 
        await wethJoin.join(owner, toWad(wethTokens), { from: owner });
        await vat.frob(ilk, owner, owner, owner, toWad(wethTokens), toWad(daiDebt), { from: owner });
        await daiJoin.exit(owner, toWad(daiTokens), { from: owner });

        // Set chi
        await pot.setChi(toRay(chi), { from: owner });
    });

    it("allows to exchange dai for chai", async() => {
        assert.equal(
            await dai.balanceOf(owner),   
            toWad(daiTokens).toString(),
            "Does not have dai"
        );
        assert.equal(
            await chai.balanceOf(owner),   
            0,
            "Does have Chai",
        );
        
        await dai.approve(chai.address, toWad(daiTokens), { from: owner }); 
        await chai.join(owner, toWad(daiTokens), { from: owner });

        // Test transfer of chai
        assert.equal(
            await chai.balanceOf(owner),   
            toWad(chaiTokens).toString(),
            "Should have chai",
        );
        assert.equal(
            await dai.balanceOf(owner),   
            0,
            "Should not have dai",
        );
    });

    describe("with chai", () => {
        beforeEach(async() => {
            await dai.approve(chai.address, toWad(daiTokens), { from: owner }); 
            await chai.join(owner, toWad(daiTokens), { from: owner });
        });

        it("allows to exchange chai for dai", async() => {
            assert.equal(
                await chai.balanceOf(owner),   
                toWad(chaiTokens).toString(),
                "Does not have chai tokens",
            );
            assert.equal(
                await dai.balanceOf(owner),   
                0,
                "Has dai tokens"
            );
            
            await chai.exit(owner, toWad(chaiTokens), { from: owner });

            // Test transfer of chai
            assert.equal(
                await dai.balanceOf(owner),   
                toWad(daiTokens).toString(),
                "Should have dai",
            );
            assert.equal(
                await chai.balanceOf(owner),   
                0,
                "Should not have chai",
            );
        });
    });
});