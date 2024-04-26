import { expect } from "chai";
import { ethers } from "hardhat";
import { CollateralizedExchange } from "../typechain-types";

describe("CollateralizedExchange", function () {
  // We define a fixture to reuse the same setup in every test.

  let CollateralizedExchange: CollateralizedExchange;
  before(async () => {
    const [owner] = await ethers.getSigners();
    const CollateralizedExchangeFactory = await ethers.getContractFactory("CollateralizedExchange");
    CollateralizedExchange = (await CollateralizedExchangeFactory.deploy(owner.address)) as CollateralizedExchange;
    await CollateralizedExchange.deployed();
  });

  describe("Deployment", function () {
    it("Should have the right message on deploy", async function () {
      expect(await CollateralizedExchange.greeting()).to.equal("Building Unstoppable Apps!!!");
    });

    it("Should allow setting a new message", async function () {
      const newGreeting = "Learn Scaffold-ETH 2! :)";

      await CollateralizedExchange.setGreeting(newGreeting);
      expect(await CollateralizedExchange.greeting()).to.equal(newGreeting);
    });
  });
});
