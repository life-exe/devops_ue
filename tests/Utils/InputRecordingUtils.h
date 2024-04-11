// My game copyright

#pragma once

#include "CoreMinimal.h"
#include "InputRecordingUtils.generated.h"

/**
 * @brief Struct representing axis data.
 */
USTRUCT()
struct FAxisData
{
    GENERATED_BODY()

    UPROPERTY()
    FName Name; /**< The name of the axis. */

    UPROPERTY()
    float Value = 0.0f; /**< The value of the axis. */
};

/**
 * @brief Struct representing action data.
 */
USTRUCT()
struct FActionData
{
    GENERATED_BODY()

    UPROPERTY()
    FName Name; /**< The name of the action. */

    UPROPERTY()
    FKey Key; /**< The key associated with the action. */

    UPROPERTY()
    bool State = false; /**< The state of the action. */
};

/**
 * @brief Struct representing input bindings data.
 */
USTRUCT()
struct FBindingsData
{
    GENERATED_BODY()

    UPROPERTY()
    TArray<FAxisData> AxisValues; /**< The array of axis values. */

    UPROPERTY()
    TArray<FActionData> ActionValues; /**< The array of action values. */

    UPROPERTY()
    float WorldTime = 0.0f; /**< The world time. */
};

/**
 * @brief Struct representing input data.
 */
USTRUCT()
struct FInputData
{
    GENERATED_BODY()

    UPROPERTY()
    TArray<FBindingsData> Bindings; /**< The array of input bindings data. */

    UPROPERTY()
    FTransform InitialTransform; /**< The initial transform. */
};
