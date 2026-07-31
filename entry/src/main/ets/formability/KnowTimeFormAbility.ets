import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit'
import { Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'KnowTimeFormAbility'
const DOMAIN = 0x0001

export default class KnowTimeFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm')
    const formDataMap = new Map<string, string | number>()
    formDataMap.set('todayMinutes', 0)
    formDataMap.set('currentTask', '开始专注')
    formDataMap.set('sessionCount', 0)
    formDataMap.set('flowScore', 0)
    return formBindingData.createFormBindingData(formDataMap)
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm, formId: %{public}s', formId)
  }

  onUpdateForm(formId: string, msg: Record<string, Object>): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm, formId: %{public}s', formId)
    const formDataMap = new Map<string, string | number>()
    formDataMap.set('todayMinutes', 45)
    formDataMap.set('currentTask', '深度学习')
    formDataMap.set('sessionCount', 3)
    formDataMap.set('flowScore', 88)
    const formData = formBindingData.createFormBindingData(formDataMap)
    formProvider.updateForm(formId, formData)
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    hilog.info(DOMAIN, TAG, 'onChangeFormVisibility')
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent, formId: %{public}s, message: %{public}s', formId, message)
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm, formId: %{public}s', formId)
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY
  }
}
