const {deployAndLinkAll} = require("./helpers/testDeployer.js")
const {increaseTime, expectEvent} = require("./helpers/utils.js")
const {createSnapshot, restoreSnapshot} = require("./helpers/snapshot.js")
const {accounts, contract, web3} = require("@openzeppelin/test-environment")
const {BN, expectRevert} = require("@openzeppelin/test-helpers")
const {expect} = require("chai")

const TBTCSystem = contract.fromArtifact("TBTCSystem")
const SatWeiPriceFeed = contract.fromArtifact("SatWeiPriceFeed")
const MockMedianizer = contract.fromArtifact("MockMedianizer")
const ECDSAKeepFactoryStub = contract.fromArtifact("ECDSAKeepFactoryStub")

describe("TBTCSystem governance", async function() {
  let tbtcSystem
  let keepFactorySelector
  let ecdsaKeepFactory
  let newKeepFactory
  let satWeiPriceFeed
  let ethBtcMedianizer
  let badEthBtcMedianizer
  let newEthBtcMedianizer

  const medianizerValue = 100000000000

  const nonSystemOwner = accounts[3]

  before(async () => {
    const {
      tbtcSystemStub,
      tbtcDepositToken,
      mockSatWeiPriceFeed,
      keepFactorySelectorStub,
      ecdsaKeepFactoryStub,
    } = await deployAndLinkAll(
      [],
      // Though deployTestDeposit deploys a TBTCSystemStub for us, we want to
      // test TBTCSystem itself.
      {
        TBTCSystemStub: TBTCSystem,
        MockSatWeiPriceFeed: SatWeiPriceFeed,
      },
    )
    // Refer to this correctly throughout the rest of the test.
    tbtcSystem = tbtcSystemStub
    ecdsaKeepFactory = ecdsaKeepFactoryStub
    keepFactorySelector = keepFactorySelectorStub
    tdt = tbtcDepositToken
    satWeiPriceFeed = mockSatWeiPriceFeed

    newKeepFactory = await ECDSAKeepFactoryStub.new()
    await newKeepFactory.setOpenKeepFeeEstimate(83)

    ethBtcMedianizer = await MockMedianizer.new()
    await ethBtcMedianizer.setValue(medianizerValue)
    satWeiPriceFeed.initialize(tbtcSystem.address, ethBtcMedianizer.address)

    badEthBtcMedianizer = await MockMedianizer.new()
    await badEthBtcMedianizer.setValue(0)
    newEthBtcMedianizer = await MockMedianizer.new()
    await newEthBtcMedianizer.setValue(1)
  })

  describe("emergencyPauseNewDeposits", async () => {
    let term

    beforeEach(async () => {
      await createSnapshot()
    })

    afterEach(async () => {
      await restoreSnapshot()
    })

    it("pauses new deposit creation", async () => {
      let allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(true)

      await tbtcSystem.emergencyPauseNewDeposits()

      allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(false)
    })

    it("pauses new deposit creation a day out", async () => {
      let allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(true)

      await increaseTime(24 * 60 * 60 + 1)
      await tbtcSystem.emergencyPauseNewDeposits()

      allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(false)
    })

    it("pauses new deposit creation 31 days out", async () => {
      let allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(true)

      await increaseTime(31 * 24 * 60 * 60 + 1)
      await tbtcSystem.emergencyPauseNewDeposits()

      allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(false)
    })

    it("pauses new deposit creation 61 days out", async () => {
      let allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(true)

      await increaseTime(61 * 24 * 60 * 60 + 1)
      await tbtcSystem.emergencyPauseNewDeposits()

      allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(false)
    })

    it("doesn't pause new deposit creation after a year has passed", async () => {
      let allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(true)

      await increaseTime(365 * 24 * 60 * 60 + 1)
      await expectRevert(
        tbtcSystem.emergencyPauseNewDeposits(),
        "emergencyPauseNewDeposits can only be called within 365 days of initialization",
      )

      allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(true)
    })

    it("reverts if msg.sender is not owner", async () => {
      await expectRevert(
        tbtcSystem.emergencyPauseNewDeposits({from: nonSystemOwner}),
        "Ownable: caller is not the owner",
      )
    })

    it("does not allows new deposit re-activation before 10 days", async () => {
      await tbtcSystem.emergencyPauseNewDeposits()
      term = await tbtcSystem.getRemainingPauseTerm()

      await increaseTime(term.toNumber() - 10) // T-10 seconds. toNumber because increaseTime doesn't support BN

      await expectRevert(
        tbtcSystem.resumeNewDeposits(),
        "Deposits are still paused",
      )
    })

    it("allows new deposit creation after 10 days", async () => {
      await tbtcSystem.emergencyPauseNewDeposits()
      term = await tbtcSystem.getRemainingPauseTerm()

      await increaseTime(term) // 10 days
      await tbtcSystem.resumeNewDeposits()
      const allowNewDeposits = await tbtcSystem.getAllowNewDeposits()
      expect(allowNewDeposits).to.equal(true)
    })

    it("reverts if emergencyPauseNewDeposits has already been called", async () => {
      await tbtcSystem.emergencyPauseNewDeposits()
      term = await tbtcSystem.getRemainingPauseTerm()

      await increaseTime(term) // 10 days
      tbtcSystem.resumeNewDeposits()

      await expectRevert(
        tbtcSystem.emergencyPauseNewDeposits(),
        "emergencyPauseNewDeposits can only be called once",
      )
    })
  })

  describe("when trying to update Keep factory info more than once", async () => {
    beforeEach(async () => {
      await createSnapshot()
    })

    afterEach(async () => {
      await restoreSnapshot()
    })

    it("does not revert if beginKeepFactorySingleShotUpdate has already been called", async () => {
      await tbtcSystem.beginKeepFactorySingleShotUpdate(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
      )

      // Should not revert.
      await tbtcSystem.beginKeepFactorySingleShotUpdate(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
      )
    })

    it("reverts if finalizeKeepFactorySingleShotUpdate has already been called", async () => {
      await tbtcSystem.beginKeepFactorySingleShotUpdate(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
      )

      const finalizationTime = await tbtcSystem.getRemainingKeepFactorySingleShotUpdateTime()
      await increaseTime(finalizationTime.toNumber() + 1) // 10 days
      await tbtcSystem.finalizeKeepFactorySingleShotUpdate()

      await expectRevert(
        tbtcSystem.beginKeepFactorySingleShotUpdate(
          "0x0000000000000000000000000000000000000001",
          "0x0000000000000000000000000000000000000002",
        ),
        "Keep factory data can only be updated once",
      )
    })

    it("reverts if finalizeKeepFactorySingleShotUpdate is called twice", async () => {
      await tbtcSystem.beginKeepFactorySingleShotUpdate(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
      )

      const finalizationTime = await tbtcSystem.getRemainingKeepFactorySingleShotUpdateTime()
      await increaseTime(finalizationTime.toNumber() + 1) // 10 days
      await tbtcSystem.finalizeKeepFactorySingleShotUpdate()

      await expectRevert(
        tbtcSystem.finalizeKeepFactorySingleShotUpdate(),
        "Change not initiated",
      )
    })
  })

  before(async () => {
    governanceTest({
      property: "signer fee",
      change: "SignerFeeDivisorUpdate",
      goodParametersWithName: [{name: "_signerFeeDivisor", value: new BN(200)}],
      badInitializationTests: {
        "smaller than or equal to 9": {
          parameters: [9],
          error:
            "Signer fee divisor must be greater than 9, for a signer fee that is <= 10%",
        },
        "greater than or equal to 5000": {
          parameters: [5000],
          error:
            "Signer fee divisor must be less than 5000, for a signer fee that is > 0.02%",
        },
      },
      verifyFinalizationEvents: (receipt, setDivisor) => {
        expectEvent(receipt, "SignerFeeDivisorUpdated", {
          _signerFeeDivisor: setDivisor,
        })
      },
      verifyFinalState: async setDivisor => {
        expect(await tbtcSystem.getSignerFeeDivisor()).to.eq.BN(setDivisor)
      },
    })

    governanceTest({
      property: "lot sizes",
      change: "LotSizesUpdate",
      goodParametersWithName: [
        {
          name: "_lotSizes",
          value: [
            new BN(10 ** 8), // required
            new BN(10 ** 6),
            new BN(10 ** 9), // upper bound
            new BN(50 * 10 ** 3), // lower bound
          ],
        },
      ],
      badInitializationTests: {
        "array is empty": {
          parameters: [[]],
          error: "Lot size array must always contain 1 BTC",
        },
        "array does not contain a 1 BTC lot size": {
          parameters: [[10 ** 7]],
          error: "Lot size array must always contain 1 BTC",
        },
        "array contains a lot size < 0.0005 BTC": {
          parameters: [[10 ** 7, 10 ** 8, 5 * 10 ** 3 - 1]],
          error: "Lot sizes less than 0.0005 BTC are not allowed",
        },
        "array contains a lot size > 10 BTC": {
          parameters: [[10 ** 7, 10 ** 9 + 1, 10 ** 8]],
          error: "Lot sizes greater than 10 BTC are not allowed",
        },
      },
      verifyFinalizationEvents: (receipt, setLotSizes) => {
        expectEvent(receipt, "LotSizesUpdated", {_lotSizes: setLotSizes})
      },
      verifyFinalState: async setLotSizes => {
        const lotSizes = await tbtcSystem.getAllowedLotSizes()
        lotSizes.forEach((_, i) => expect(_).to.eq.BN(setLotSizes[i]))
      },
    })

    governanceTest({
      property: "collateralization thresholds",
      change: "CollateralizationThresholdsUpdate",
      goodParametersWithName: [
        {name: "_initialCollateralizedPercent", value: new BN(213)},
        {name: "_undercollateralizedThresholdPercent", value: new BN(156)},
        {
          name: "_severelyUndercollateralizedThresholdPercent",
          value: new BN(128),
        },
      ],
      badInitializationTests: {
        "contain initial collateralized percent > 300": {
          parameters: [301, 130, 120],
          error: "Initial collateralized percent must be <= 300%",
        },
        "contain initial collateralized percent < 100": {
          parameters: [99, 130, 120],
          error: "Initial collateralized percent must be >= 100%",
        },
        "contain undercollateralized threshold > initial collateralized percent": {
          parameters: [150, 160, 120],
          error:
            "Undercollateralized threshold must be < initial collateralized percent",
        },
        "contain severe undercollateralized threshold > undercollateralized threshold": {
          parameters: [150, 130, 131],
          error:
            "Severe undercollateralized threshold must be < undercollateralized threshold",
        },
      },
      verifyFinalizationEvents: (
        receipt,
        setInitial,
        setUnder,
        setSeverelyUnder,
      ) => {
        expectEvent(receipt, "CollateralizationThresholdsUpdated", {
          _initialCollateralizedPercent: setInitial,
          _undercollateralizedThresholdPercent: setUnder,
          _severelyUndercollateralizedThresholdPercent: setSeverelyUnder,
        })
      },
      verifyFinalState: async (setInitial, setUnder, setSeverelyUnder) => {
        expect(await tbtcSystem.getInitialCollateralizedPercent()).to.eq.BN(
          setInitial,
        )
        expect(
          await tbtcSystem.getUndercollateralizedThresholdPercent(),
        ).to.eq.BN(setUnder)
        expect(
          await tbtcSystem.getSeverelyUndercollateralizedThresholdPercent(),
        ).to.eq.BN(setSeverelyUnder)
      },
    })

    governanceTest({
      property: "keep factory single-shot update",
      change: "KeepFactorySingleShotUpdate",
      goodParametersWithName: [
        {
          name: "_factorySelector",
          value: keepFactorySelector.address,
        },
        {
          name: "_ethBackedFactory",
          value: newKeepFactory.address,
        },
      ],
      badInitializationTests: {
        "factory selector is unset": {
          parameters: [
            "0x0000000000000000000000000000000000000000",
            "0x0000000000000000000000000000000000000000",
          ],
          error: "Factory selector must be a nonzero address",
        },
      },
      verifyFinalizationEvents: async (
        receipt,
        setFactorySelector,
        setEthBackedFactory,
      ) => {
        expectEvent(receipt, "KeepFactorySingleShotUpdated", {
          _factorySelector: setFactorySelector,
          _ethBackedFactory: setEthBackedFactory,
        })
      },
      verifyFinalState: async () => {
        const mockDepositOwner = accounts[1]
        const mockDeposit = accounts[2]
        await tdt.forceMint(mockDepositOwner, web3.utils.toBN(mockDeposit))

        keepFactorySelector.setFullyBackedMode()
        // Expect this to work normally, and update to the new factory for the
        // next call.
        await tbtcSystem.requestNewKeep(5, 10, 0, 123, {
          from: mockDeposit,
          value: await ecdsaKeepFactory.openKeepFeeEstimate.call(),
        })

        // This should fail as the _ethBackedFactory is not a real contract
        // address, so dereferencing it will go boom.
        await tbtcSystem.requestNewKeep(5, 10, 0, 123, {
          from: mockDeposit,
          value: await newKeepFactory.openKeepFeeEstimate.call(),
        })

        expect(await newKeepFactory.keepOwner.call()).to.equal(mockDeposit)
      },
    })

    governanceTest({
      property: "the ETHBTC feeds with a new entry",
      change: "EthBtcPriceFeedAddition",
      timeDelayGetter: "getPriceFeedGovernanceTimeDelay",
      goodParametersWithName: [
        {name: "_priceFeed", value: newEthBtcMedianizer.address},
      ],
      badInitializationTests: {
        "adding inactive feed": {
          parameters: [badEthBtcMedianizer.address],
          error: "Cannot add inactive feed",
        },
      },
      verifyFinalizationEvents: (receipt, newFeedAddress) => {
        expectEvent(receipt, "EthBtcPriceFeedAdded", {
          _priceFeed: newFeedAddress,
        })
      },
      verifyFinalState: async () => {
        // disable current feed
        await ethBtcMedianizer.setValue(0)

        // check new feed
        expect(await satWeiPriceFeed.getWorkingEthBtcFeed()).to.equal(
          newEthBtcMedianizer.address,
        )
      },
      badFinalizationTests: {
        "finalizing inactive feed": {
          parameters: [newEthBtcMedianizer.address],
          beforeFinalizing: async () => newEthBtcMedianizer.setValue(0),
          error: "Cannot add inactive feed",
        },
      },
    })
  })

  function governanceTest({
    property,
    change,
    timeDelayGetter,
    goodParametersWithName,
    badInitializationTests,
    verifyFinalizationEvents,
    verifyFinalState,
    badFinalizationTests,
  }) {
    timeDelayGetter = timeDelayGetter || "getGovernanceTimeDelay"
    badInitializationTests = badInitializationTests || {}
    badFinalizationTests = badFinalizationTests || {}

    function parametersAsList(parametersWithName) {
      const parametersList = []
      for (let i = 0; i < parametersWithName.length; ++i) {
        parametersList[i] = parametersWithName[i].value
      }

      return parametersList
    }
    function parametersAsObject(parametersWithName) {
      const parametersObject = []
      for (let i = 0; i < parametersWithName.length; ++i) {
        parametersObject[parametersWithName[i].name] =
          parametersWithName[i].value
      }

      return parametersObject
    }

    function tweakParameters(parametersWithName) {
      const newParametersWithName = []

      for (let i = 0; i < parametersWithName.length; ++i) {
        const {name, value} = parametersWithName[i]
        let updatedValue = value
        if (value instanceof BN) {
          updatedValue = value.add(new BN(1))
        } else if (typeof value == "number") {
          updatedValue = value + 1
        } else if (value instanceof String && value.startsWith("0x")) {
          // Assume address, generate one.
          updatedValue = "0x"
          for (let j = 0; j < 20; ++i) {
            updatedValue += (
              "0" + Math.floor(Math.random() * 255).toString("hex")
            ).substr(-2)
          }
        }

        newParametersWithName.push({name: name, value: updatedValue})
      }

      return [
        parametersAsObject(newParametersWithName),
        parametersAsList(newParametersWithName),
      ]
    }

    const goodParameters = parametersAsList(goodParametersWithName)
    const goodParametersByName = parametersAsObject(goodParametersWithName)

    async function invoke(prefix, suffix, params) {
      const fn = tbtcSystem[`${prefix || ""}${change}${suffix || ""}`]
      if (!fn) {
        console.error(`${prefix}${change}${suffix}`)
      }
      return fn.apply(tbtcSystem, params)
    }

    describe(`when updating ${property}`, async () => {
      beforeEach(async () => {
        await createSnapshot()
      })

      afterEach(async () => {
        await restoreSnapshot()
      })

      describe("when initiating the update", async () => {
        it("executes and fires the update start event", async () => {
          const receipt = await invoke("begin", "", goodParameters)

          expectEvent(receipt, `${change}Started`, goodParametersByName)
        })

        it("does not commit updates immediately", async () => {
          await invoke("begin", "", goodParameters)

          let failed = true
          try {
            await verifyFinalState(...goodParameters)
            failed = false
          } catch (error) {
            failed = true
          }

          if (!failed) {
            expect.fail("Expected final state verification to fail.")
          }
        })

        it("overrides previous update and resets timer", async () => {
          await invoke("begin", "", goodParameters)
          await increaseTime(50)

          const governanceTime = await tbtcSystem[timeDelayGetter].call()

          const [updatedParametersByName, updatedParameters] = tweakParameters(
            goodParametersWithName,
          )
          const receipt = await invoke("begin", "", updatedParameters)
          const remainingTime = await invoke("getRemaining", "Time")

          expectEvent(receipt, `${change}Started`, updatedParametersByName)
          expect([
            remainingTime.toString(),
            remainingTime.toString() - 1,
          ]).to.include(governanceTime.toString())
        })

        it("reverts if msg.sender != owner", async () => {
          await expectRevert.unspecified(
            invoke("begin", "", goodParameters.concat([{from: accounts[1]}])),
          )
        })

        for (const [scenario, props] of Object.entries(
          badInitializationTests,
        )) {
          const {parameters, error} = props

          it(`reverts when ${scenario}`, async () => {
            await expectRevert(invoke("begin", "", parameters), error)
          })
        }
      })

      describe("when finalizing the update", async () => {
        it("reverts if the governance timer has not elapsed", async () => {
          await invoke("begin", "", goodParameters)

          await expectRevert(
            invoke("finalize"),
            "Governance delay has not elapsed.",
          )
        })

        it("reverts if a change has not been initiated", async () => {
          await expectRevert(invoke("finalize"), "Change not initiated.")
        })

        for (const [scenario, props] of Object.entries(badFinalizationTests)) {
          const {beforeFinalizing, parameters, error} = props

          it(`reverts when ${scenario}`, async () => {
            await invoke("begin", "", parameters)
            const remainingTime = await invoke("getRemaining", "Time")
            await increaseTime(remainingTime.toNumber() + 1)

            if (beforeFinalizing) {
              await beforeFinalizing()
            }

            await expectRevert(invoke("finalize"), error)
          })
        }

        it(`updates ${property} and fires event if the governance timer has elapsed`, async () => {
          await invoke("begin", "", goodParameters)
          const remainingTime = await invoke("getRemaining", "Time")
          await increaseTime(remainingTime.toNumber() + 1)

          const receipt = await invoke("finalize")
          await verifyFinalizationEvents(receipt, ...goodParameters)
          await verifyFinalState(...goodParameters)
        })
      })
    })
  }
})
