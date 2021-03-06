module Moderator
  class TagsController < ApplicationController
    before_action :moderator_only

    def edit
    end

    def update
      TagBatchJob.perform_later(params[:tag][:antecedent], params[:tag][:consequent], CurrentUser.user.id, CurrentUser.ip_addr)
      redirect_to edit_moderator_tag_path, :notice => "Post changes queued"
    end

    def error
      redirect_to edit_moderator_tag_path, :notice => "Error"
    end
  end
end
