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
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./../shared/utils');

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

        await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.
    });

    it('should setup vat', async() => {
        console.log("    Limits: " + await vat.Line());
        console.log("    Spot: " + (await vat.ilks(ilk)).spot);
        console.log("    Rate: " + (await vat.ilks(ilk)).rate);
    });

    it('should join funds', async() => {
        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            0,
        );

        await weth.deposit({ from: owner, value: wethTokens});
        await weth.approve(wethJoin.address, wethTokens, { from: owner }); 
        await wethJoin.join(owner, wethTokens, { from: owner });

        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            wethTokens.toString(),
            'We should have joined ' + wethTokens + ' weth.'
        );
    });

    describe('with funds joined', () => {
        /* beforeEach(async() => {
            await weth.deposit({ from: owner, value: wethTokens});
            await weth.approve(wethJoin.address, wethTokens, { from: owner }); 
            await wethJoin.join(owner, wethTokens, { from: owner });
        }); */

        it('should deposit collateral', async() => {
            await vat.frob(ilk, owner, owner, owner, wethTokens, 0, { from: owner });
            
            assert.equal(
                (await vat.urns(ilk, owner)).ink,   
                wethTokens.toString(),
                'We should have ' + wethTokens + ' weth as collateral.',
            );

            // Revert to previous state
            await vat.frob(ilk, owner, owner, owner, wethTokens.mul(-1), 0, { from: owner });
        });

        it('should deposit collateral and borrow Dai', async() => {
            await vat.frob(ilk, owner, owner, owner, wethTokens, daiDebt, { from: owner });

            assert.equal(
                (await vat.urns(ilk, owner)).ink,   
                wethTokens.toString(),
                'We should have ' + wethTokens + ' weth as collateral.',
            );
            assert.equal(
                (await vat.urns(ilk, owner)).art,   
                daiDebt.toString(),
                'Owner should have ' + daiDebt + ' dai debt.',
            );

            await daiJoin.exit(owner, daiTokens, { from: owner });

            assert.equal(
                await dai.balanceOf(owner),   
                daiTokens.toString(),
                'Owner should have ' + daiTokens + ' dai.',
            );

            // Revert to previous state
            await daiJoin.join(owner, daiTokens, { from: owner });
            await vat.frob(ilk, owner, owner, owner, wethTokens.mul(-1), daiDebt.mul(-1), { from: owner });
        });

        /* it('should not allow borrowing without enough collateral', async() => {
            // spot = 1.5
            // rate = 1.25
            // debt * rate <= collateral * spot
            // collateral = (rate / spot) * debt
            // 120 * 1.25 <= 100 * 1.5
            await vat.frob(ilk, owner, owner, owner, wethTokens, daiDebt, { from: owner }); // weth 100, dai debt 120
            assert.equal(
                (await vat.urns(ilk, owner)).ink,   
                wethTokens.toString(),
                'We should have ' + wethTokens + ' weth as collateral.',
            );
            assert.equal(
                (await vat.urns(ilk, owner)).art,   
                daiDebt.toString(),
                'We should have ' + daiDebt + ' normalized dai debt.',
            );
            await expectRevert(
                vat.frob(ilk, owner, owner, owner, -1, 0, { from: owner }), // Not a wei less collateral
                'Vat/not-safe',
            );
            await expectRevert(
                vat.frob(ilk, owner, owner, owner, 0, 1, { from: owner }), // Not a wei more debt
                'Vat/not-safe',
            );
            await daiJoin.exit(owner, daiTokens, { from: owner }); // We can borrow weth * spot / rate (dai 150)
            await expectRevert(
                daiJoin.exit(owner, 1, { from: owner }), // Not a wei more borrowing
                'Vat/sub',
            );
        }); */

        /* describe('with collateral deposited', () => {
            beforeEach(async() => {
                await vat.frob(ilk, owner, owner, owner, wethTokens, 0, { from: owner });
            });
     
            it('should withdraw collateral', async() => {
                const unfrob = '-' + wethTokens;
                await vat.frob(ilk, owner, owner, owner, unfrob, 0, { from: owner });

                assert.equal(
                    (await vat.urns(ilk, owner)).ink,   
                    '0'
                );
            });

            it('should borrow Dai', async() => {

                await vat.frob(ilk, owner, owner, owner, 0, daiDebt, { from: owner });

                assert.equal(
                    (await vat.dai(owner)).toString(),   
                    daiTokens + '000000000000000000000000000', // dai balances in vat are in RAD
                );

                await daiJoin.exit(owner, daiTokens, { from: owner }); // Shouldn't we be able to exit vatBalance?

                assert.equal(
                    await dai.balanceOf(owner),   
                    daiTokens.toString(),
                );
            });

            describe('with dai borrowed', () => {
                beforeEach(async() => {
                    await vat.frob(ilk, owner, owner, owner, 0, daiDebt, { from: owner });
                    await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.
                    await daiJoin.exit(owner, daiTokens, { from: owner });
                });

                it('should return Dai', async() => {
                    let undai = '-' + daiDebt;

                    await daiJoin.join(owner, daiTokens, { from: owner });
                    await vat.frob(ilk, owner, owner, owner, 0, undai, { from: owner });

                    assert.equal(
                        await vat.dai(owner),   
                        '0'
                    );
                });

                it('should return Dai and withdraw collateral', async() => {
                    let unfrob = '-' + wethTokens;
                    let undai =  '-' + daiDebt;

                    await daiJoin.join(owner, daiTokens, { from: owner });
                    await vat.frob(ilk, owner, owner, owner, unfrob, undai, { from: owner });
                    //let ink2 = (await vat.dai(ilk, owner)).ink.toString()
                    
                    assert.equal(
                        await vat.dai(owner),   
                        '0'
                    );
                    assert.equal(
                        (await vat.urns(ilk, owner)).ink,   
                        '0'
                    );
                });
            });
        }); */
    });
});