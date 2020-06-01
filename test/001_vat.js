const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const ERC20 = artifacts.require('TestERC20');

const { expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad } = require('./shared/utils')

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
    const spot  = 1.5;
    const rate  = 1.25;
    const daiDebt = 120;    // Dai debt for `frob`: 120
    const daiTokens = daiDebt * rate;  // Dai we can borrow: 120 * rate
    const wethTokens = daiDebt * rate / spot; // Collateral we join: 120 * rate / spot


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await ERC20.new(0, { from: owner }); 
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner }); 
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(ilk, spotName, toRay(spot), { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?

        await vat.rely(wethJoin.address, { from: owner }); // `owner` authorizing `wethJoin` to operate for `vat`
        await vat.rely(daiJoin.address, { from: owner });  // `owner` authorizing `daiJoin` to operate for `vat`
        await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.

        await vat.fold(ilk, vat.address, toRay(rate - 1), { from: owner }); // 1 + 0.25
    });

    it('should setup vat', async() => {
        assert(
            (await vat.ilks(ilk)).spot,
            toRay(spot),
            'spot not initialized',
        )
        assert(
            (await vat.ilks(ilk)).rate,
            toRay(rate),
            'rate not initialized',
        )
    });

    it('should join funds', async() => {
        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            0,
        );

        await weth.mint(owner, toWad(wethTokens), { from: owner });
        await weth.approve(wethJoin.address, toWad(wethTokens), { from: owner }); 
        await wethJoin.join(owner, toWad(wethTokens), { from: owner }); // We join 150 weth

        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            toWad(wethTokens).toString(),
            'We should have joined ' + toWad(wethTokens) + ' weth.'
        );
    });

    describe('with funds joined', () => {
        beforeEach(async() => {
            await weth.mint(owner, toWad(wethTokens), { from: owner });
            await weth.approve(wethJoin.address, toWad(wethTokens), { from: owner }); 
            await wethJoin.join(owner, toWad(wethTokens), { from: owner });
        });

        it('should deposit collateral', async() => {
            await vat.frob(ilk, owner, owner, owner, toWad(wethTokens), 0, { from: owner });
            
            assert.equal(
                (await vat.urns(ilk, owner)).ink,   
                toWad(wethTokens).toString(),
                'We should have ' + toWad(wethTokens) + ' weth as collateral.',
            );
        });

        it('should deposit collateral and borrow Dai', async() => {
            
            await vat.frob(ilk, owner, owner, owner, toWad(wethTokens), toWad(daiDebt), { from: owner });
            //let ink = (await vat.urns(ilk, owner)).ink;
            // const pow = web3.utils.toBN('47')
            // const daiRad =  web3.utils.toBN('10').pow(pow).toString(); // 100 dai in RAD
            /* assert.equal(
                await vat.dai(owner),   
                '125000000000000000000000000000000000000000000000',
            ); */
            assert.equal(
                (await vat.urns(ilk, owner)).ink,   
                toWad(wethTokens).toString(),
                'We should have ' + toWad(wethTokens) + ' weth as collateral.',
            );
            assert.equal(
                (await vat.urns(ilk, owner)).art,   
                toWad(daiDebt).toString(),
                'Owner should have ' + toWad(daiDebt) + ' dai debt.',
            );

            await daiJoin.exit(owner, toWad(daiTokens), { from: owner }); // Shouldn't we be able to exit vatBalance?

            assert.equal(
                await dai.balanceOf(owner),   
                toWad(daiTokens).toString(),
                'Owner should have ' + toWad(daiTokens) + ' dai.',
            );
        });

        it('should not allow borrowing without enough collateral', async() => {
            // spot = 1.5
            // rate = 1.25
            // debt * rate <= collateral * spot
            // collateral = (rate / spot) * debt
            // 120 * 1.25 <= 100 * 1.5
            await vat.frob(ilk, owner, owner, owner, toWad(wethTokens), toWad(daiDebt), { from: owner }); // weth 100, dai debt 120
            assert.equal(
                (await vat.urns(ilk, owner)).ink,   
                toWad(wethTokens).toString(),
                'We should have ' + toWad(wethTokens) + ' weth as collateral.',
            );
            assert.equal(
                (await vat.urns(ilk, owner)).art,   
                toWad(daiDebt).toString(),
                'We should have ' + toWad(daiDebt) + ' normalized dai debt.',
            );
            await expectRevert(
                vat.frob(ilk, owner, owner, owner, -1, 0, { from: owner }), // Not a wei less collateral
                'Vat/not-safe',
            );
            await expectRevert(
                vat.frob(ilk, owner, owner, owner, 0, 1, { from: owner }), // Not a wei more debt
                'Vat/not-safe',
            );
            await daiJoin.exit(owner, toWad(daiTokens), { from: owner }); // We can borrow weth * spot / rate (dai 150)
            await expectRevert(
                daiJoin.exit(owner, 1, { from: owner }), // Not a wei more borrowing
                'Vat/sub',
            );
        });

        describe('with collateral deposited', () => {
            beforeEach(async() => {
                await vat.frob(ilk, owner, owner, owner, toWad(wethTokens), 0, { from: owner });
            });
     
            it('should withdraw collateral', async() => {
                const unfrob = '-' + toWad(wethTokens);
                await vat.frob(ilk, owner, owner, owner, unfrob, 0, { from: owner });

                assert.equal(
                    (await vat.urns(ilk, owner)).ink,   
                    '0'
                );
            });

            it('should borrow Dai', async() => {

                await vat.frob(ilk, owner, owner, owner, 0, toWad(daiDebt), { from: owner });

                assert.equal(
                    (await vat.dai(owner)).toString(),   
                    toWad(daiTokens) + '000000000000000000000000000', // dai balances in vat are in RAD
                );

                await daiJoin.exit(owner, toWad(daiTokens), { from: owner }); // Shouldn't we be able to exit vatBalance?

                assert.equal(
                    await dai.balanceOf(owner),   
                    toWad(daiTokens).toString(),
                );
            });

            describe('with dai borrowed', () => {
                beforeEach(async() => {
                    await vat.frob(ilk, owner, owner, owner, 0, toWad(daiDebt), { from: owner });
                    await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.
                    await daiJoin.exit(owner, toWad(daiTokens), { from: owner });
                });

                it('should return Dai', async() => {
                    let undai = '-' + toWad(daiDebt);

                    await daiJoin.join(owner, toWad(daiTokens), { from: owner });
                    await vat.frob(ilk, owner, owner, owner, 0, undai, { from: owner });

                    assert.equal(
                        await vat.dai(owner),   
                        '0'
                    );
                });

                it('should return Dai and withdraw collateral', async() => {
                    let unfrob = '-' + toWad(wethTokens);
                    let undai =  '-' + toWad(daiDebt);

                    await daiJoin.join(owner, toWad(daiTokens), { from: owner });
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