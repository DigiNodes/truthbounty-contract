// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IStressTestEvents
/// @notice Versioned stress-test telemetry emitted by the event architecture harness.
/// @dev The harness validates amplification bounds before emitting this event.
interface IStressTestEvents {
    event StressTestCompleted(
        bytes32 indexed testId,
        uint32 amplificationRatioBps,
        uint32 sampleCount,
        bool passed,
        uint64 timestamp,
        uint16 version
    );
}
