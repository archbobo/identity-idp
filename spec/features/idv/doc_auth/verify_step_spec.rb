require 'rails_helper'

feature 'doc auth verify step' do
  include IdvStepHelper
  include DocAuthHelper

  before do
    enable_doc_auth
    complete_doc_auth_steps_before_verify_step
  end

  it 'is on the correct page' do
    expect(page).to have_current_path(idv_doc_auth_verify_step)
    expect(page).to have_content(t('doc_auth.headings.verify'))
  end

  it 'proceeds to the next page upon confirmation' do
    click_idv_continue

    expect(page).to have_current_path(idv_doc_auth_success_step)
  end

  it 'proceeds to the address page if the user clicks change address' do
    click_link t('doc_auth.buttons.change_address')

    expect(page).to have_current_path(idv_address_path)
  end

  it 'proceeds to the ssn page if the user clicks change address' do
    click_link t('doc_auth.buttons.change_ssn')

    expect(page).to have_current_path(idv_address_path)
  end
end
