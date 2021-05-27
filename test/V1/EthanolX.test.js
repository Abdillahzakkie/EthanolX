const UniswapV2Router02 = artifacts.require('IUniswapV2Router02');
const UniswapFactory = artifacts.require('IFactory');
const IWETH = artifacts.require('IWETH');
const EthanolX = artifacts.require('EthanolX');
const { ZERO_ADDRESS } = require('@openzeppelin/test-helpers/src/constants');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');


const toWei = _amount => web3.utils.toWei(_amount.toString());
const fromWei = _amount => web3.utils.fromWei(_amount.toString());
const toChecksumAddress = _account => web3.utils.toChecksumAddress(_account);

contract("EthanolX", async ([deployer, admin, user1, user2, user3]) => {
    const name = "EthanolX";
    const symbol = "ENOL-X";

    const UniswapFactoryAddress = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
    const UniswapV2Router02Address = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    const WETHAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

    const _createLiquidityPair = async () => {
        const _pairAddress = await this.uniswapFactory.createPair.call(this.WETH.address, this.token.address, { from: deployer });
        await this.uniswapFactory.createPair(this.WETH.address, this.token.address, { from: deployer });
        return _pairAddress;
    }

    const _addLiquidity = async () => {
        await this.WETH.approve(this.router.address, toWei(10), { from: deployer });
        await this.token.approve(this.router.address, toWei(10), { from: deployer });

        await this.router.addLiquidity(
            this.WETH.address,
            this.token.address,
            toWei(10),
            toWei(10),
            toWei(10),
            toWei(10),
            Math.floor(Date.now() / 1000) + (60 * 10),
            { from: deployer }
        );
    }

    const transfer = async (sender, recipient, amount) => await this.token.transfer(recipient, amount, { from: sender });

    beforeEach(async () => {
        this.uniswapFactory = await UniswapFactory.at(UniswapFactoryAddress);
        this.router = await UniswapV2Router02.at(UniswapV2Router02Address);
        this.WETH = await IWETH.at(WETHAddress);
        this.token = await EthanolX.new(name, symbol, { from: deployer });

        await this.token.setUniswap(this.WETH.address);

        const _amount = toWei(1000);
        await transfer(deployer, user1, _amount);
        await transfer(deployer, user2, _amount);
        await transfer(deployer, user3, _amount);

        // const _pairAddress = await _createLiquidityPair();
        // await _addLiquidity();
    })

    describe('deployment', () => {
        it("should deploy contracts properly", async () => {
            expect(this.uniswapFactory.address).not.equal(ZERO_ADDRESS);
            expect(this.router.address).not.equal(ZERO_ADDRESS);
            expect(this.WETH.address).not.equal(ZERO_ADDRESS);
            expect(this.token.address).not.equal(ZERO_ADDRESS);
        })

        it("should set token name properly", async () => {

        })
    })
    
})