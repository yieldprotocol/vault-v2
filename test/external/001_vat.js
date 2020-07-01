const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const ERC20 = artifacts.require('TestERC20');
const Weth = artifacts.require('WETH9');

const { expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('Vat', async (accounts) =>  {
    const [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;

    let ilk = web3.utils.fromAscii('weth')
    let Line = web3.utils.fromAscii('Line')
    let spotName = web3.utils.fromAscii('spot')
    let linel = web3.utils.fromAscii('line')
    const limits =  toRad(10000);
    const spot  = toRay(1.5);
    const rate  = toRay(1.22);
    const daiDebt = toWad(120);    // Dai debt for `frob`: 120
    const daiTokens = mulRay(daiDebt, rate);  // Dai we can borrow: 120 * rate
    const wethTokens = divRay(daiTokens, spot); // Collateral we join: 120 * rate / spot

    // console.log("spot: " + spot);
    // console.log("rate: " + rate);            
    // console.log("daiDebt: " + daiDebt);
    // console.log("daiTokens: " + daiTokens);
    // console.log("wethTokens: " + wethTokens);

    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await Weth.new({ from: owner }); 
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner }); 
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Vat permissions
        await vat.rely(wethJoin.address, { from: owner }); // `owner` authorizing `wethJoin` to operate for `vat`
        await vat.rely(daiJoin.address, { from: owner });  // `owner` authorizing `daiJoin` to operate for `vat`
        await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.
    });

    it('should setup vat', async() => {
        assert(
            (await vat.ilks(ilk)).spot,
            spot,
            'spot not initialized',
        )
        assert(
            (await vat.ilks(ilk)).rate,
            rate,
            'rate not initialized',
        )
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
        beforeEach(async() => {
            await weth.deposit({ from: owner, value: wethTokens});
            await weth.approve(wethJoin.address, wethTokens, { from: owner }); 
            await wethJoin.join(owner, wethTokens, { from: owner });
        });

        it('should deposit collateral', async() => {
            await vat.frob(ilk, owner, owner, owner, wethTokens, 0, { from: owner });
            
            assert.equal(
                (await vat.urns(ilk, owner)).ink,   
                wethTokens.toString(),
                'We should have ' + wethTokens + ' weth as collateral.',
            );
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

            await daiJoin.exit(owner, daiTokens, { from: owner }); // Shouldn't we be able to exit vatBalance?

            assert.equal(
                await dai.balanceOf(owner),   
                daiTokens.toString(),
                'Owner should have ' + daiTokens + ' dai.',
            );
        });

        it('should not allow borrowing without enough collateral', async() => {
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
        });

        describe('with collateral deposited', () => {
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
        });
    });
});