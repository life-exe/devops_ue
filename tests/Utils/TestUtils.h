#pragma once

#if WITH_AUTOMATION_TESTS

#include "CoreMinimal.h"
#include "Engine/Blueprint.h"
#include "Tests/AutomationCommon.h"
#include "Blueprint/WidgetBlueprintLibrary.h"
#include "Blueprint/WidgetTree.h"
#include "Blueprint/UserWidget.h"

namespace LifeExe
{
namespace Test
{
/**
 * @brief Struct representing a payload for testing purposes.
 * @tparam Type1 The type of the test value.
 * @tparam Type2 The type of the expected value.
 */
template <typename Type1, typename Type2>
struct TestPayload
{
    Type1 TestValue;                      /**< The test value. */
    Type2 ExpectedValue;                  /**< The expected value. */
    float Tolerance = KINDA_SMALL_NUMBER; /**< Tolerance for comparison. */
};

/**
 * @brief Macro to iterate over enum values.
 * @param TYPE The type of the enum.
 * @param EnumElem The variable representing each enum element.
 */
#define ENUM_LOOP_START(TYPE, EnumElem)                                        \
    for (int32 Index = 0; Index < StaticEnum<TYPE>()->NumEnums() - 1; ++Index) \
    {                                                                          \
        const auto EnumElem = static_cast<TYPE>(StaticEnum<TYPE>()->GetValueByIndex(Index));
#define ENUM_LOOP_END }

/**
 * @brief Iterates over each enum value.
 * @tparam EnumType The type of the enum.
 * @tparam FunctionType The type of the function.
 * @param Function The function to call for each enum value.
 */
template <typename EnumType, typename FunctionType>
void ForEach(FunctionType&& Function)
{
    const UEnum* Enum = StaticEnum<EnumType>();
    for (int32 i = 0; i < Enum->NumEnums(); ++i)
    {
        Function(static_cast<EnumType>(Enum->GetValueByIndex(i)));
    }
}

/**
 * @brief Creates an instance of a Blueprint in the world.
 * @tparam T The type of the object to spawn.
 * @param World The world to spawn the object in.
 * @param Name The name of the Blueprint asset.
 * @param Transform The transform to spawn the object with.
 * @return The spawned object, or nullptr if failed.
 */
template <typename T>
T* CreateBlueprint(UWorld* World, const FString& Name, const FTransform& Transform = FTransform::Identity)
{
    const UBlueprint* Blueprint = LoadObject<UBlueprint>(nullptr, *Name);
    return (World && Blueprint) ? World->SpawnActor<T>(Blueprint->GeneratedClass, Transform) : nullptr;
}

/**
 * @brief Creates an instance of a Blueprint in the world in a deferred manner.
 * @tparam T The type of the object to spawn.
 * @param World The world to spawn the object in.
 * @param Name The name of the Blueprint asset.
 * @param Transform The transform to spawn the object with.
 * @return The spawned object, or nullptr if failed.
 */
template <typename T>
T* CreateBlueprintDeferred(UWorld* World, const FString& Name, const FTransform& Transform = FTransform::Identity)
{
    const UBlueprint* Blueprint = LoadObject<UBlueprint>(nullptr, *Name);
    return (World && Blueprint) ? World->SpawnActorDeferred<T>(Blueprint->GeneratedClass, Transform) : nullptr;
}

/**
 * @brief Helper class for managing the scope of a level for testing.
 */
class LevelScope
{
public:
    /**
     * @brief Construct a new LevelScope object.
     * @param MapName The name of the level to open.
     */
    LevelScope(const FString& MapName) { AutomationOpenMap(MapName); }

    /**
     * @brief Destructor that closes the level scope.
     */
    ~LevelScope() { ADD_LATENT_AUTOMATION_COMMAND(FExitGameCommand); }
};

/**
 * @brief Gets the test game world.
 * @return The test game world.
 */
UWorld* GetTestGameWorld();

/**
 * @brief Calls a function by name with parameters on an object.
 * @param Object The object to call the function on.
 * @param FuncName The name of the function to call.
 * @param Params The parameters to pass to the function.
 */
void CallFuncByNameWithParams(UObject* Object, const FString& FuncName, const TArray<FString>& Params);

/**
 * @brief Latent command that waits until a specified callback or timeout.
 */
class FUntilLatentCommand : public IAutomationLatentCommand
{
public:
    /**
     * @brief Construct a new FUntilLatentCommand object.
     * @param InCallback The callback function.
     * @param InTimeoutCallback The timeout callback function.
     * @param InTimeout The timeout duration.
     */
    FUntilLatentCommand(TFunction<void()> InCallback, TFunction<void()> InTimeoutCallback, float InTimeout = 5.0f);

    /**
     * @brief Updates the latent command.
     * @return True if the command is completed, false otherwise.
     */
    virtual bool Update() override;

private:
    TFunction<void()> Callback;        /**< The callback function. */
    TFunction<void()> TimeoutCallback; /**< The timeout callback function. */
    float Timeout;                     /**< The timeout duration. */
};

/**
 * @brief Gets the index of an action binding by name.
 * @param InputComp The input component to search in.
 * @param ActionName The name of the action.
 * @param InputEvent The input event.
 * @return The index of the action binding, or INDEX_NONE if not found.
 */
int32 GetActionBindingIndexByName(UInputComponent* InputComp, const FString& ActionName, EInputEvent InputEvent);

/**
 * @brief Gets the index of an axis binding by name.
 * @param InputComp The input component to search in.
 * @param AxisName The name of the axis.
 * @return The index of the axis binding, or INDEX_NONE if not found.
 */
int32 GetAxisBindingIndexByName(UInputComponent* InputComp, const FString& AxisName);

/**
 * @brief Gets the directory for test data.
 * @return The directory path for test data.
 */
FString GetTestDataDir();

/**
 * @brief Finds a widget in the game world by its class.
 * @tparam T The type of the widget to find.
 * @return The found widget, or nullptr if not found.
 */
template <class T>
T* FindWidgetByClass()
{
    TArray<UUserWidget*> Widgets;
    UWidgetBlueprintLibrary::GetAllWidgetsOfClass(GetTestGameWorld(), Widgets, T::StaticClass(), false);
    return Widgets.Num() != 0 ? Cast<T>(Widgets[0]) : nullptr;
}

/**
 * @brief Finds a widget in the hierarchy by name.
 * @param Widget The root widget to search from.
 * @param WidgetName The name of the widget to find.
 * @return The found widget, or nullptr if not found.
 */
UWidget* FindWidgetByName(const UUserWidget* Widget, const FName& WidgetName);

/**
 * @brief Simulates an input action on an input component.
 * @param InputComponent The input component to simulate on.
 * @param ActionName The name of the action.
 * @param Key The key to simulate.
 */
void DoInputAction(UInputComponent* InputComponent, const FString& ActionName, const FKey& Key);

/**
 * @brief Simulates pressing the jump action.
 * @param InputComponent The input component to simulate on.
 */
void JumpPressed(UInputComponent* InputComponent);

/**
 * @brief Simulates pressing the pause action.
 * @param InputComponent The input component to simulate on.
 */
void PausePressed(UInputComponent* InputComponent);

/**
 * @brief Latent command for taking a screenshot.
 */
class FTakeScreenshotLatentCommand : public IAutomationLatentCommand
{
public:
    /**
     * @brief Construct a new FTakeScreenshotLatentCommand object.
     * @param InScreenshotName The name of the screenshot.
     */
    FTakeScreenshotLatentCommand(const FString& InScreenshotName);

    /**
     * @brief Destructor.
     */
    virtual ~FTakeScreenshotLatentCommand();

protected:
    const FString ScreenshotName;    /**< The name of the screenshot. */
    bool ScreenshotRequested{false}; /**< Flag indicating if screenshot is requested. */
    bool CommandCompleted{false};    /**< Flag indicating if command is completed. */

    /**
     * @brief Callback when screenshot is taken and compared.
     */
    virtual void OnScreenshotTakenAndCompared();
};

/**
 * @brief Latent command for taking a game screenshot.
 */
class FTakeGameScreenshotLatentCommand : public FTakeScreenshotLatentCommand
{
public:
    /**
     * @brief Construct a new FTakeGameScreenshotLatentCommand object.
     * @param InScreenshotName The name of the screenshot.
     */
    FTakeGameScreenshotLatentCommand(const FString& InScreenshotName);

    /**
     * @brief Updates the latent command.
     * @return True if the command is completed, false otherwise.
     */
    virtual bool Update() override;
};

/**
 * @brief Latent command for taking a UI screenshot.
 */
class FTakeUIScreenshotLatentCommand : public FTakeScreenshotLatentCommand
{
public:
    /**
     * @brief Construct a new FTakeUIScreenshotLatentCommand object.
     * @param InScreenshotName The name of the screenshot.
     */
    FTakeUIScreenshotLatentCommand(const FString& InScreenshotName);

    /**
     * @brief Updates the latent command.
     * @return True if the command is completed, false otherwise.
     */
    virtual bool Update() override;

private:
    bool ScreenshotSetupDone{false}; /**< Flag indicating if screenshot setup is done. */

    /**
     * @brief Callback when screenshot is taken and compared.
     */
    virtual void OnScreenshotTakenAndCompared() override;

    /**
     * @brief Sets buffer visualization mode.
     * @param VisualizeBuffer The buffer to visualize.
     */
    void SetBufferVisualization(const FName& VisualizeBuffer);
};

/**
 * @brief Closes the level for a specific world.
 * @param World The world to close.
 */
void SpecCloseLevel(UWorld* World);

/**
 * @brief Gets the value of a property by name.
 * @tparam ObjectClass The type of the object.
 * @tparam PropertyClass The type of the property.
 * @param Obj The object to get the property from.
 * @param PropName The name of the property.
 * @return The value of the property.
 */
template <class ObjectClass, class PropertyClass>
PropertyClass GetPropertyValueByName(ObjectClass* Obj, const FString& PropName)
{
    if (!Obj) return PropertyClass();
    for (TFieldIterator<FProperty> PropIt(Obj->StaticClass()); PropIt; ++PropIt)
    {
        const FProperty* Property = *PropIt;
        if (Property && Property->GetName().Equals(PropName))
        {
            return *Property->ContainerPtrToValuePtr<PropertyClass>(Obj);
        }
    }
    return PropertyClass();
}

}  // namespace Test
}  // namespace LifeExe

#endif
