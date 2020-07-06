const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('./Chai');
const Treasury = artifacts.require('Treasury');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Treasury - Saving', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let chai;
    let treasury;

    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")

    const limits =  toRad(10000);
    const spot = toRay(1.5);
    const rate = toRay(1.25);
    const chi = toRay(1.2);
    
    const daiDebt = toWad(120);
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    const chaiTokens = divRay(daiTokens, chi);

    beforeEach(async() => {
        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); 
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Setup pot
        pot = await Pot.new(vat.address);

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.hope(daiJoin.address, { from: user });

        // Borrow some dai
        await weth.deposit({ from: user, value: wethTokens});
        await weth.approve(wethJoin.address, wethTokens, { from: user }); 
        await wethJoin.join(user, wethTokens, { from: user });
        await vat.frob(ilk, user, user, user, wethTokens, daiDebt, { from: user });
        await daiJoin.exit(user, daiTokens, { from: user });

        // Set chi
        await pot.setChi(chi, { from: owner });
        
        treasury = await Treasury.new(
            vat.address,
            weth.address,
            dai.address,
            wethJoin.address,
            daiJoin.address,
            pot.address,
            chai.address,
        );
        await treasury.orchestrate(owner, { from: owner });
    });

    /* it("get the size of the contract", async() => {
        console.log();
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log("|  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |");
        console.log("·····················|··················|··················|···················");
        
        const bytecode = treasury.constructor._json.bytecode;
        const deployed = treasury.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "|  " + (treasury.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log();
    }); */

    it("allows to save dai", async() => {
        assert.equal(
            await chai.balanceOf(treasury.address),
            0,
            "Treasury has chai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has savings in dai units"
        );
        assert.equal(
            await dai.balanceOf(user),
            daiTokens.toString(),
            "User does not have dai",
        );
        
        await dai.approve(treasury.address, daiTokens, { from: user }); 
        await treasury.pushDai(user, daiTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai"
        );
        assert.equal(
            await treasury.savings.call(),
            daiTokens.toString(),
            "Treasury should have " + daiTokens + " savings in dai units, instead has " + await treasury.savings.call(),
        );
        assert.equal(
            await dai.balanceOf(user),
            0,
            "User should not have dai",
        );
    });

    it("allows to save chai", async() => {
        assert.equal(
            await chai.balanceOf(treasury.address),
            0,
            "Treasury has chai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has savings in dai units"
        );
        assert.equal(
            await dai.balanceOf(user),
            daiTokens.toString(),
            "User does not have dai",
        );
        
        await dai.approve(chai.address, daiTokens, { from: user });
        await chai.join(user, daiTokens, { from: user });
        await chai.approve(treasury.address, chaiTokens, { from: user }); 
        await treasury.pushChai(user, chaiTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai"
        );
        assert.equal(
            await treasury.savings.call(),
            daiTokens.toString(),
            "Treasury should report savings in dai units"
        );
        assert.equal(
            await chai.balanceOf(user),
            0,
            "User should not have chai",
        );
    });

    describe("with savings", () => {
        beforeEach(async() => {
            await dai.approve(treasury.address, daiTokens, { from: user }); 
            await treasury.pushDai(user, daiTokens, { from: owner });
        });

        it("pulls dai from savings", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens.toString(),
                "Treasury does not have chai"
            );
            assert.equal(
                await treasury.savings.call(),
                daiTokens.toString(),
                "Treasury does not report savings in dai units"
            );
            assert.equal(
                await dai.balanceOf(user),
                0,
                "User has dai",
            );
            
            await treasury.pullDai(user, daiTokens, { from: owner });

            assert.equal(
                await chai.balanceOf(treasury.address),
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                await treasury.savings.call(),
                0,
                "Treasury should not have savings in dai units"
            );
            assert.equal(
                await dai.balanceOf(user),
                daiTokens.toString(),
                "User should have dai",
            );
        });


        it("pulls chai from savings", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens.toString(),
                "Treasury does not have chai"
            );
            assert.equal(
                await treasury.savings.call(),
                daiTokens.toString(),
                "Treasury does not report savings in dai units"
            );
            assert.equal(
                await dai.balanceOf(user),
                0,
                "User has dai",
            );
            
            await treasury.pullChai(user, chaiTokens, { from: owner });

            assert.equal(
                await chai.balanceOf(treasury.address),
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                await treasury.savings.call(),
                0,
                "Treasury should not have savings in dai units"
            );
            assert.equal(
                await chai.balanceOf(user),
                chaiTokens.toString(),
                "User should have chai",
            );
        });
    });
});