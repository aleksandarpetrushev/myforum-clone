Rails.application.routes.draw do
  get "health", to: "health#show"
  get "ready", to: "health#ready"

  namespace :api do
    post "session", to: "sessions#create"

    resources :events, only: [:index, :show, :update, :destroy] do
      member do
        post :register
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
      resources :notifications, only: :index
    end
  end
end
