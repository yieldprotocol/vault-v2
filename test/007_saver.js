const Saver = artifacts.require('./Saver');
const ERC20 = artifacts.require("./TestERC20");

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('Saver', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let saver;
    let chai;

    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('45');
    const supply = web3.utils.toWei("1000");
    const limits =  web3.utils.toBN('10000').mul(web3.utils.toBN('10').pow(RAD)).toString(); // 10000 * 10**45

    beforeEach(async() => {
        chai = await ERC20.new(supply, { from: owner }); 
        saver = await Saver.new(chai.address);
        await saver.grantAccess(user, { from: owner });
    });

    it("allows to save chai", async() => {
        assert.equal(
            (await saver.savings()),   
            web3.utils.toWei("0")
        );
        
        let amount = web3.utils.toWei("500");
        await chai.mint(user, amount, { from: user });
        await chai.approve(saver.address, amount, { from: user }); 
        await saver.join(user, amount, { from: user });

        // Test transfer of collateral
        assert.equal(
            (await saver.savings()),   
            web3.utils.toWei("500")
        );
        assert.equal(
            (await chai.balanceOf(user)),   
            0
        );
    });

    describe("with savings", () => {
        beforeEach(async() => {
            let amount = web3.utils.toWei("500");
            await chai.mint(user, amount, { from: user });
            await chai.approve(saver.address, amount, { from: user }); 
            await saver.join(user, amount, { from: user });
        });

        it("allows to withdraw chai", async() => {
            assert.equal(
                (await chai.balanceOf(user)),   
                web3.utils.toWei("0")
            );
            
            let amount = web3.utils.toWei("500");
            await saver.exit(user, amount, { from: user });

            // Test transfer of collateral
            assert.equal(
                (await saver.savings()),   
                0
            );
            assert.equal(
                (await chai.balanceOf(user)),   
                web3.utils.toWei("500")
            );
        });
    });
});