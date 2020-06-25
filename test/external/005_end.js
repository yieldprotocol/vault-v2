const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const ERC20 = artifacts.require('TestERC20');
const Weth = artifacts.require('WETH9');
const End = artifacts.require('End');

const { expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('End', async (accounts) =>  {
    const [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let end;
    let ilk = web3.utils.fromAscii("ETH-A")
    const limits =  toRad(10000);
    const spot  = toRay(1.5);
    const tag  = divRay(toRay(1), spot);
    const fix  = divRay(toRay(1), spot);
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

        await vat.file(ilk, web3.utils.fromAscii('spot'), spot, { from: owner });
        await vat.file(ilk, web3.utils.fromAscii('line'), limits, { from: owner });
        await vat.file(web3.utils.fromAscii('Line'), limits); 
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        end = await End.new({ from: owner });
        await end.file(web3.utils.fromAscii("vat"), vat.address);

        // Vat permissions
        await vat.rely(wethJoin.address, { from: owner }); // `owner` authorizing `wethJoin` to operate for `vat`
        await vat.rely(daiJoin.address, { from: owner });  // `owner` authorizing `daiJoin` to operate for `vat`
        await vat.rely(end.address, { from: owner }); // `owner` authorizing `end` to operate for `vat`
        await end.rely(owner, { from: owner });       // `owner` authorizing himself to operate for `end`
        await vat.hope(daiJoin.address, { from: owner });  // `owner` allowing daiJoin to move his dai.
        await vat.hope(wethJoin.address, { from: owner });  // `owner` allowing wethJoin to move his weth.
    });

    it('should setup vat', async() => {
        assert(
            (await vat.ilks(ilk)).spot,
            spot,
            'spot not initialized',
        );
        assert(
            (await vat.ilks(ilk)).rate,
            rate,
            'rate not initialized',
        );
        assert(
            await vat.live.call(),
            1,
            'live not initialised',
        );
        assert(
            await end.live.call(),
            1,
            'live not initialised',
        );
    });

    describe('With dai borrowed', () => {
        beforeEach(async() => {
            // Borrow some dai
            await weth.deposit({ from: owner, value: wethTokens});
            await weth.approve(wethJoin.address, wethTokens, { from: owner });
            await wethJoin.join(owner, wethTokens, { from: owner });
            await vat.frob(ilk, owner, owner, owner, wethTokens, daiDebt, { from: owner });
            await daiJoin.exit(owner, daiTokens, { from: owner });
            // Deposit one extra wei
            await weth.deposit({ from: owner, value: 1});
            await weth.approve(wethJoin.address, 1, { from: owner });
            await wethJoin.join(owner, 1, { from: owner });
        });

        it('can cage vat and end', async() => {
            await end.cage({ from: owner });
            
            assert(
                await vat.live.call(),
                0,
                'vat not caged',
            );
            assert(
                await end.live.call(),
                0,
                'end not caged',
            );
        });

        describe('With contracts caged', () => {
            beforeEach(async() => {
                await end.cage({ from: owner });
            });
    
            it('can set tag manually', async() => {
                await end.setTag(ilk, tag, { from: owner });
                
                assert(
                    await end.tag(ilk),
                    tag,
                    'tag not set',
                );
            });

            describe('With tag set', () => {
                beforeEach(async() => {
                    await end.setTag(ilk, tag, { from: owner });
                });
        
                it('can settle debts', async() => {
                    await end.skim(ilk, owner, { from: owner });
                    
                    assert.equal(
                        (await vat.urns(ilk, owner)).ink,
                        1,
                        'Owner should have 1 wei weth as collateral.',
                    );
                    assert.equal(
                        (await vat.urns(ilk, owner)).art,
                        0,
                        'Owner should have no dai debt.',
                    );
                });

                describe('With debts settled', () => {
                    beforeEach(async() => {
                        await end.skim(ilk, owner, { from: owner });
                    });
            
                    it('can free collateral', async() => {
                        await end.free(ilk, { from: owner });
                        await wethJoin.exit(owner, 1, { from: owner });
                        
                        assert.equal(
                            (await vat.urns(ilk, owner)).ink,
                            0,
                            'Owner should have no collateral in vat',
                        );
                        assert.equal(
                            await weth.balanceOf(owner),
                            1,
                            'Owner should have 1 weth in hand',
                        );
                    });

                    it('can set debt manually', async() => {
                        await end.setDebt(0, { from: owner });
                        
                        assert(
                            await end.debt.call(),
                            1,
                            'debt not set',
                        );
                    });

                    describe('With system debt', () => {
                        beforeEach(async() => {
                            await end.setDebt(1, { from: owner });
                        });
                
                        it('can pack dai', async() => {
                            await daiJoin.join(owner, daiTokens, { from: owner });
                            await vat.hope(end.address, { from: owner});
                            await end.pack(daiTokens, { from: owner });
                            
                            assert.equal(
                                await end.bag(owner),
                                daiTokens.toString(),
                                'Owner should have packed ' + daiTokens + ' dai in the bag',
                            );
                        });

                        describe('With dai packed', () => {
                            beforeEach(async() => {
                                await daiJoin.join(owner, daiTokens, { from: owner });
                                await vat.hope(end.address, { from: owner });
                                await end.pack(daiTokens, { from: owner });
                            });
                    
                            it('can set fix manually', async() => {
                                await end.setFix(ilk, fix, { from: owner });
                                
                                assert(
                                    await end.fix(ilk),
                                    fix,
                                    'fix not set',
                                );
                            });

                            describe('With fix set', () => {
                                beforeEach(async() => {
                                    await end.setFix(ilk, fix, { from: owner });
                                });
                        
                                it('can cash weth', async() => {
                                    await end.cash(ilk, daiTokens, { from: owner });
                                    await wethJoin.exit(owner, wethTokens, { from: owner });
                                    
                                    assert.equal(
                                        await weth.balanceOf(owner),
                                        wethTokens.toString(),
                                        'Owner should have ' + wethTokens + ' in hand',
                                    );
                                });
                            });
                        });
                    });
                });
            });
        });
    });
});