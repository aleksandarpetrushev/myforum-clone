Rails.application.routes.draw do
  get "health", to: "health#show"
  get "ready", to: "health#ready"

  namespace :api do
    post "session", to: "sessions#create"

    resources :events, only: [:index, :show, :create, :update, :destroy]
    resources :organizations, only: :index

    resources :registrations, only: :create do
      collection do
        post :cancel
      end
    end

    resources :topics, only: :index do
      member do
        post :follow
        delete :follow, action: :unfollow
      end
    end

    namespace :me do
      resources :registrations, only: :index
      resources :organizations, only: :index
      resources :notifications, only: :index do
        member do
          post :read
        end
        collection do
          post :read_all
        end
      end
      resource :notification_preferences, only: [:show, :update]
    end
  end
end
