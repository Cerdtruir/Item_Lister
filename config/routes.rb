Rails.application.routes.draw do
  get 'items/new_takealot', to: 'items#new_takealot', as: 'new_takealot_form'

  resources :items do
    collection do
      post :create_from_takealot
      get 'scan_barcode'
      post 'create_from_barcode'
      get 'mobile_scan'
      post 'lookup_barcode'
      post 'create_from_mobile_scan'
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root 'items#mobile_scan'
end

