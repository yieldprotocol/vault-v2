const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Jug = artifacts.require("Jug");
const Pot = artifacts.require("Pot");
const Chai = artifacts.require("Chai");
const GasToken = artifacts.require("GasToken1");
const WethOracle = artifacts.require("WethOracle");
const ChaiOracle = artifacts.require("ChaiOracle");
const Treasury = artifacts.require("Treasury");
const Dealer = artifacts.require("Dealer");

const { expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('Vat', async (accounts, network) =>  {
    const [ owner, user ] = accounts;

    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let chai;
    let gasToken;
    let wethOracle;
    let chaiOracle;
    let treasury;
    let dealer;

    let ilk = web3.utils.fromAscii('ETH-A');
    let spot;
    let rate;
    let wethTokens;
    let daiTokens;
    let daiDebt;

    beforeEach(async() => {
        /* if (network !== 'development') {
            vatAddress = fixed_addrs[network].vatAddress ;
            wethAddress = fixed_addrs[network].wethAddress;
            wethJoinAddress = fixed_addrs[network].wethJoinAddress;
            daiAddress = fixed_addrs[network].daiAddress;
            daiJoinAddress = fixed_addrs[network].daiJoinAddress;
            potAddress = fixed_addrs[network].potAddress;
            fixed_addrs[network].chaiAddress ? 
                (chaiAddress = fixed_addrs[network].chaiAddress)
                : (chaiAddress = (await Chai.deployed()).address);
            fixed_addrs[network].gasTokenAddress ? 
                (gasTokenAddress = fixed_addrs[network].gasTokenAddress)
                : (gasTokenAddress = (await GasToken.deployed()).address);
        } else {
            vat = await Vat.deployed();
            weth = await Weth.deployed();
            wethJoin = await GemJoin.deployed();
            dai = await ERC20.deployed();
            daiJoin = await DaiJoin.deployed();
            jug = await Jug.deployed();
            pot = await Pot.deployed();
            chai = await Chai.deployed();
            gasToken = await GasToken.deployed();
        } */

        vat = await Vat.deployed();
        weth = await Weth.deployed();
        wethJoin = await GemJoin.deployed();
        dai = await ERC20.deployed();
        daiJoin = await DaiJoin.deployed();
        jug = await Jug.deployed();
        pot = await Pot.deployed();
        chai = await Chai.deployed();
        gasToken = await GasToken.deployed();

        spot  = (await vat.ilks(ilk)).spot;
        rate  = (await vat.ilks(ilk)).rate;
        wethTokens = toWad(1);
        daiTokens = mulRay(wethTokens.toString(), spot.toString());
        daiDebt = divRay(daiTokens.toString(), rate.toString());

        await vat.hope(daiJoin.address, { from: user }); // `user` allowing daiJoin to move his dai.
    });

    it('should setup vat', async() => {
        console.log("    Limits: " + await vat.Line());
        console.log("    Spot: " + (await vat.ilks(ilk)).spot);
        console.log("    Rate: " + (await vat.ilks(ilk)).rate);
    });

    it('should deposit collateral', async() => {
        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            0,
        );

        await weth.deposit({ from: user, value: wethTokens});
        await weth.approve(wethJoin.address, wethTokens, { from: user }); 
        await wethJoin.join(user, wethTokens, { from: user });

        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            wethTokens.toString(),
            'User should have joined ' + wethTokens + ' weth.'
        );

        await vat.frob(ilk, user, user, user, wethTokens, 0, { from: user });
        
        assert.equal(
            (await vat.urns(ilk, user)).ink,   
            wethTokens.toString(),
            'User should have ' + wethTokens + ' weth as collateral.',
        );
    });

    it('should borrow Dai', async() => {
        await vat.frob(ilk, user, user, user, 0, daiDebt, { from: user });

        assert.equal(
            (await vat.urns(ilk, user)).art,   
            daiDebt.toString(),
            'User should have ' + daiDebt + ' dai debt.',
        );

        await daiJoin.exit(user, daiTokens, { from: user });

        assert.equal(
            await dai.balanceOf(user),   
            daiTokens.toString(),
            'User should have ' + daiTokens + ' dai.',
        );
    });

    it('should repay Dai', async() => {
        await daiJoin.join(user, daiTokens, { from: user });
        assert.equal(
            await dai.balanceOf(user),   
            0,
            'User should have no dai.',
        );

        await vat.frob(ilk, user, user, user, 0, daiDebt.mul(-1), { from: user });

        assert.equal(
            (await vat.urns(ilk, user)).art,   
            0,
            'Owner should have no dai debt.',
        );
    });

    it('should withdraw collateral', async() => {
        await vat.frob(ilk, user, user, user, wethTokens.mul(-1), 0, { from: user });

        assert.equal(
            (await vat.urns(ilk, user)).ink,   
            0,
            'User should have no weth as collateral.',
        );

        await wethJoin.exit(user, wethTokens, { from: user });

        assert.equal(
            await weth.balanceOf(user),   
            wethTokens.toString(),
            'User should have ' + wethTokens + ' weth.',
        );
    });
});