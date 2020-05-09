const Mint = artifacts.require('Mint');
const Lender = artifacts.require('Lender');
const Saver = artifacts.require('Saver');
const Chai = artifacts.require('Chai');
const YDai = artifacts.require('YDai');
const ERC20 = artifacts.require('TestERC20');
const DaiJoin = artifacts.require('DaiJoin');
const GemJoin = artifacts.require('GemJoin');
const Vat= artifacts.require('Vat');
const Pot= artifacts.require('Pot');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { balance, BN, constants, ether, expectEvent, expectRevert, send } = require('@openzeppelin/test-helpers');

contract('Chai', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let pot;
    let lender;
    let saver;
    let dai;
    let yDai;
    let chai;
    let weth;
    let daiJoin;
    let wethJoin;
    let mint;
    let amount = web3.utils.toWei("100");

    const ilk = web3.utils.fromAscii("ETH-A")
    const Line = web3.utils.fromAscii("Line")
    const spot = web3.utils.fromAscii("spot")
    const linel = web3.utils.fromAscii("line")

    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('45');
    const supply = web3.utils.toWei("1000");
    const limits =  web3.utils.toBN('10000').mul(web3.utils.toBN('10').pow(RAD)).toString(); // 10000 * 10**45

    beforeEach(async() => {
        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.rely(vat.address, { from: owner });

        weth = await ERC20.new(supply, { from: owner }); 
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

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
        await vat.rely(chai.address, { from: owner });

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup lender
        lender = await Lender.new(
            dai.address,        // dai
            weth.address,       // weth
            daiJoin.address,    // daiJoin
            wethJoin.address,   // wethJoin
            vat.address,        // vat
        );
        await vat.rely(lender.address, { from: owner }); //?

        // Setup saver
        saver = await Saver.new(chai.address);

        // Setup mint
        mint = await Mint.new(
            lender.address,
            saver.address,
            dai.address,
            yDai.address,
            chai.address,
            { from: owner },
        );
        await yDai.grantAccess(mint.address, { from: owner });
        await lender.grantAccess(mint.address, { from: owner });
        await saver.grantAccess(mint.address, { from: owner });

        // Borrow dai
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        let wethTokens = web3.utils.toWei("500");
        await weth.approve(wethJoin.address, wethTokens, { from: owner });
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, amount, { from: owner });
        await daiJoin.exit(owner, amount, { from: owner });
    });

    describe("chai tests", async() => {

        it("allows to exchange dai for chai", async() => {
            assert.equal(
                (await chai.balanceOf(owner)),   
                web3.utils.toWei("0")
            );
            
            await dai.approve(chai.address, amount, { from: owner }); 
            await chai.join(owner, amount, { from: owner });

            assert.equal(
                (await chai.balanceOf(owner)),   
                amount
            );
        });

        describe("with chai", () => {
            beforeEach(async() => {
                await dai.approve(chai.address, amount, { from: owner }); 
                await chai.join(owner, amount, { from: owner });
            });

            it("allows to exchange chai for dai", async() => {
                assert.equal(
                    (await chai.balanceOf(owner)),   
                    amount,
                );
                
                await chai.exit(owner, amount, { from: owner });

                assert.equal(
                    (await chai.balanceOf(owner)),   
                    web3.utils.toWei("0")
                );
            });
        });
    });

    describe("mint tests", async() => {
        /* it("can grab dai", async() => {
            assert.equal(
                (await dai.balanceOf(owner)),   
                amount,
                "Owner does not have dai",
            );
            assert.equal(
                (await dai.balanceOf(mint.address)),   
                0
            );
            await dai.approve(mint.address, amount, { from: owner });
            await mint.grab(amount, { from: owner });

            assert.equal(
                (await dai.balanceOf(mint.address)),   
                amount,
            );
        }); */

        it("mint: mints yDai in exchange for dai, chai goes to Saver", async() => {
            assert.equal(
                (await dai.balanceOf(owner)),   
                amount,
                "Owner does not have dai",
            );
            assert.equal(
                (await chai.balanceOf(mint.address)),   
                0,
                "Mint has chai",
            );
            assert.equal(
                (await yDai.balanceOf(owner)),   
                0,
                "Owner has yDai"
            );
            assert.equal(
                (await dai.balanceOf(mint.address)),   
                0,
                "Mint has dai",
            );
            await dai.approve(mint.address, amount, { from: owner });
            await mint.mint(amount, { from: owner });

            assert.equal(
                (await chai.balanceOf(saver.address)),   
                amount,
                "Saver should have chai",
            );
            assert.equal(
                (await yDai.balanceOf(owner)),   
                amount,
                "Owner should have yDai"
            );
            assert.equal(
                (await dai.balanceOf(mint.address)),   
                0,
                "Mint should have no dai",
            );
        });

        describe("with yDai", async() => {
            beforeEach(async() => {
                await dai.approve(mint.address, amount, { from: owner });
                await mint.mint(amount, { from: owner });
            });


            it("redeem: burns yDai to return dai", async() => {
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    amount,
                    "Owner does not have yDai",
                );
                assert.equal(
                    (await chai.balanceOf(mint.address)),   
                    amount,
                    "Mint does not have chai",
                );
                assert.equal(
                    (await dai.balanceOf(mint.address)),   
                    0,
                    "Mint has dai",
                );

                await yDai.approve(mint.address, amount, { from: owner });
                await mint.redeem(amount, { from: owner });

                assert.equal(
                    (await dai.balanceOf(mint.address)),   
                    0,
                    "Mint should have no dai",
                );
                assert.equal(
                    (await dai.balanceOf(owner)),   
                    amount,
                    "Owner should have dai",
                );
            });

            /* it("can spit dai", async() => {
                assert.equal(
                    (await dai.balanceOf(mint.address)),   
                    amount,
                    "Mint does not have dai",
                );
                assert.equal(
                    (await dai.balanceOf(owner)),   
                    0,
                    "Owner has dai",
                );

                await mint.spit(amount, { from: owner });

                assert.equal(
                    (await dai.balanceOf(mint.address)),   
                    0,
                    "Mint should have no dai",
                );
                assert.equal(
                    (await dai.balanceOf(owner)),   
                    amount,
                    "Owner should have dai",
                );
            }); */

            /* it("can convert dai to chai", async() => {
                assert.equal(
                    (await dai.balanceOf(mint.address)),   
                    amount,
                    "Mint does not have dai",
                );
                assert.equal(
                    (await chai.balanceOf(mint.address)),   
                    0,
                    "Mint should have no chai",
                );

                await mint.toChai(amount, { from: owner });

                assert.equal(
                    (await chai.balanceOf(mint.address)),   
                    amount,
                );
                assert.equal(
                    (await dai.balanceOf(mint.address)),   
                    0,
                    "Mint should have no dai",
                );
            }); */

            /* describe("with chai", async() => {
                beforeEach(async() => {
                    await mint.mint(amount, { from: owner });
                });

                it("can convert chai to dai", async() => {
                    assert.equal(
                        (await chai.balanceOf(mint.address)),   
                        amount,
                    );
                    assert.equal(
                        (await dai.balanceOf(mint.address)),   
                        0,
                        "Mint should have no dai",
                    );

                    await mint.toDai(amount, { from: owner });

                    assert.equal(
                        (await dai.balanceOf(mint.address)),   
                        amount,
                        "Mint does not have dai",
                    );
                    assert.equal(
                        (await chai.balanceOf(mint.address)),   
                        0,
                        "Mint should have no chai",
                    );
                });
            }); */
        });
    });
});