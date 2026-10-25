// My game copyright

#pragma once

#include "<Path>/Utils/InputRecordingUtils.h"
#include "CoreMinimal.h"

namespace LifeExe
{
namespace Test
{

/**
 * @brief Utility class for handling JSON operations
 */
class JsonUtils
{
public:
    /**
     * @brief Writes input data to a JSON file.
     * @param FileName The name of the JSON file to write to.
     * @param InputData The input data to write.
     * @return True if the data is successfully written, false otherwise.
     */
    static bool WriteInputData(const FString& FileName, const FInputData& InputData);

    /**
     * @brief Reads input data from a JSON file.
     * @param FileName The name of the JSON file to read from.
     * @param InputData The input data to read into.
     * @return True if the data is successfully read, false otherwise.
     */
    static bool ReadInputData(const FString& FileName, FInputData& InputData);
};

}  // namespace Test
}  // namespace LifeExe
