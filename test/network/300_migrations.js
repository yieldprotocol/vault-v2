const Migrations = artifacts.require('Migrations');

contract('Migrations', async (accounts) =>  {

    let [ owner ] = accounts;
    let migrations;

    beforeEach(async() => {
        migrations = await Migrations.deployed();
    });

    it("contracts registered", async() => {
        const length = await migrations.length();
        for (let i = 0; i < length; i++) {
            const name = await migrations.names(i);
            const address = await migrations.contracts(name);
            console.log((bytes32ToString(name) + ": ").padEnd(16, ' ') + address);
        }
    });
});

function bytes32ToString(text) {
    return web3.utils.toAscii(text).replace(/\0/g, '');
}
