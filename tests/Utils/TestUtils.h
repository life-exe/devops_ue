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
template <typename Type1, typename Type2>
struct TestPayload
{
    Type1 TestValue;
    Type2 ExpectedValue;
    float Tolerance = KINDA_SMALL_NUMBER;
};

#define ENUM_LOOP_START(TYPE, EnumElem)                                        \
    for (int32 Index = 0; Index < StaticEnum<TYPE>()->NumEnums() - 1; ++Index) \
    {                                                                          \
        const auto EnumElem = static_cast<TYPE>(StaticEnum<TYPE>()->GetValueByIndex(Index));
#define ENUM_LOOP_END }

template <typename EnumType, typename FunctionType>
void ForEach(FunctionType&& Function)
{
    const UEnum* Enum = StaticEnum<EnumType>();
    for (int32 i = 0; i < Enum->NumEnums(); ++i)
    {
        Function(static_cast<EnumType>(Enum->GetValueByIndex(i)));
    }
}

template <typename T>
T* CreateBlueprint(UWorld* World, const FString& Name, const FTransform& Transform = FTransform::Identity)
{
    const UBlueprint* Blueprint = LoadObject<UBlueprint>(nullptr, *Name);
    return (World && Blueprint) ? World->SpawnActor<T>(Blueprint->GeneratedClass, Transform) : nullptr;
}

template <typename T>
T* CreateBlueprintDeferred(UWorld* World, const FString& Name, const FTransform& Transform = FTransform::Identity)
{
    const UBlueprint* Blueprint = LoadObject<UBlueprint>(nullptr, *Name);
    return (World && Blueprint) ? World->SpawnActorDeferred<T>(Blueprint->GeneratedClass, Transform) : nullptr;
}

class LevelScope
{
public:
    LevelScope(const FString& MapName) { AutomationOpenMap(MapName); }
    ~LevelScope() { ADD_LATENT_AUTOMATION_COMMAND(FExitGameCommand); }
};

UWorld* GetTestGameWorld();

void CallFuncByNameWithParams(UObject* Object, const FString& FuncName, const TArray<FString>& Params);

class FUntilLatentCommand : public IAutomationLatentCommand
{
public:
    FUntilLatentCommand(TFunction<void()> InCallback, TFunction<void()> InTimeoutCallback, float InTimeout = 5.0f);
    virtual bool Update() override;

private:
    TFunction<void()> Callback;
    TFunction<void()> TimeoutCallback;
    float Timeout;
};

int32 GetActionBindingIndexByName(UInputComponent* InputComp, const FString& ActionName, EInputEvent InputEvent);
int32 GetAxisBindingIndexByName(UInputComponent* InputComp, const FString& AxisName);

FString GetTestDataDir();

template <class T>
T* FindWidgetByClass()
{
    TArray<UUserWidget*> Widgets;
    UWidgetBlueprintLibrary::GetAllWidgetsOfClass(GetTestGameWorld(), Widgets, T::StaticClass(), false);
    return Widgets.Num() != 0 ? Cast<T>(Widgets[0]) : nullptr;
}

UWidget* FindWidgetByName(const UUserWidget* Widget, const FName& WidgetName);

void DoInputAction(UInputComponent* InputComponent, const FString& ActionName, const FKey& Key);
void JumpPressed(UInputComponent* InputComponent);
void PausePressed(UInputComponent* InputComponent);

class FTakeScreenshotLatentCommand : public IAutomationLatentCommand
{
public:
    FTakeScreenshotLatentCommand(const FString& InScreenshotName);
    virtual ~FTakeScreenshotLatentCommand();

protected:
    const FString ScreenshotName;
    bool ScreenshotRequested{false};
    bool CommandCompleted{false};

    virtual void OnScreenshotTakenAndCompared();
};

class FTakeGameScreenshotLatentCommand : public FTakeScreenshotLatentCommand
{
public:
    FTakeGameScreenshotLatentCommand(const FString& InScreenshotName);

    virtual bool Update() override;
};

class FTakeUIScreenshotLatentCommand : public FTakeScreenshotLatentCommand
{
public:
    FTakeUIScreenshotLatentCommand(const FString& InScreenshotName);
    virtual bool Update() override;

private:
    bool ScreenshotSetupDone{false};

    virtual void OnScreenshotTakenAndCompared() override;
    void SetBufferVisualization(const FName& VisualizeBuffer);
};

void SpecCloseLevel(UWorld* World);

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
