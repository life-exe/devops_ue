// My game copyright

#include "<Path>/Utils/JsonUtils.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonWriter.h"
#include "Serialization/JsonReader.h"
#include "JsonObjectConverter.h"
#include "Misc/FileHelper.h"

DEFINE_LOG_CATEGORY_STATIC(LogJsonUtils, All, All);

using namespace LifeExe::Test;

bool JsonUtils::WriteInputData(const FString& FileName, const FInputData& InputData)
{
    TSharedPtr<FJsonObject> MainJsonObject = FJsonObjectConverter::UStructToJsonObject(InputData);
    if (!MainJsonObject.IsValid()) return false;

    FString OutputString;
    TSharedRef<TJsonWriter<>> JsonWriter = TJsonWriterFactory<>::Create(&OutputString);

    if (!FJsonSerializer::Serialize(MainJsonObject.ToSharedRef(), JsonWriter))
    {
        UE_LOG(LogJsonUtils, Error, TEXT("JSON serialization error"));
        return false;
    }

    if (!JsonWriter->Close())
    {
        UE_LOG(LogJsonUtils, Error, TEXT("JSON writer closing error"));
        return false;
    }

    if (!FFileHelper::SaveStringToFile(OutputString, *FileName))
    {
        UE_LOG(LogJsonUtils, Error, TEXT("File saving error: %s"), *FileName);
        return false;
    }

    return true;
}

bool JsonUtils::ReadInputData(const FString& FileName, FInputData& InputData)
{
    FString FileContentString;
    if (!FFileHelper::LoadFileToString(FileContentString, *FileName))
    {
        UE_LOG(LogJsonUtils, Error, TEXT("File opening error"));
        return false;
    }

    TSharedRef<TJsonReader<>> JsonReader = TJsonReaderFactory<>::Create(FileContentString);
    TSharedPtr<FJsonObject> MainJsonObject;
    if (!FJsonSerializer::Deserialize(JsonReader, MainJsonObject))
    {
        UE_LOG(LogJsonUtils, Error, TEXT("JSON deserialization error"));
        return false;
    }

    return FJsonObjectConverter::JsonObjectToUStruct(MainJsonObject.ToSharedRef(), &InputData, 0, 0);
}
