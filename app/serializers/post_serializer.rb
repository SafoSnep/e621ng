class PostSerializer < ActiveModel::Serializer
  def tags
    tags = {}
    TagCategory.categories.each do |category|
      tags[category] = object.typed_tags(category)
    end
    tags
  end

  def file
    file_attributes = {
        width: object.image_width,
        height: object.image_height,
        ext: object.file_ext,
        size: object.file_size,
        md5: object.md5,
        url: nil
    }
    if object.visible?
      file_attributes[:url] = object.file_url
    end
    file_attributes
  end

  def preview
    dims = object.preview_dimensions
    preview_attributes = {
        width: dims[1],
        height: dims[0],
        url: nil
    }
    if object.visible?
      preview_attributes[:url] = object.preview_file_url
    end
    preview_attributes
  end

  def sample
    sample_attributes = {
        has: object.has_large?,
        height: object.large_image_height,
        width: object.large_image_width,
        url: nil
    }
    if object.visible?
      sample_attributes[:url] = object.large_file_url
    end
    sample_attributes
  end

  def score
    {
        up: object.up_score,
        down: object.down_score,
        total: object.score
    }
  end

  def flags
    {
        pending: object.is_pending,
        flagged: object.is_flagged,
        note_locked: object.is_note_locked,
        status_locked: object.is_status_locked,
        rating_locked: object.is_rating_locked,
        deleted: object.is_deleted
    }
  end

  def sources
    object.source.split("\n")
  end

  def pools
    object.pool_ids
  end

  def relationships
    {
        parent_id: object.parent_id,
        has_children: object.has_children,
        has_active_children: object.has_active_children,
        children: object.children_ids&.split(' ')&.map(&:to_i) || []
    }
  end

  def locked_tags
    object.locked_tags&.split(' ') || []
  end

  def is_favorited
    object.is_favorited?
  end

  def own_vote
    object.own_vote&.score || 0
  end

  attributes :id, :created_at, :updated_at, :file, :preview, :sample, :score, :tags, :locked_tags, :change_seq, :flags,
             :rating, :fav_count, :sources, :pools, :relationships, :approver_id, :uploader_id, :description,
             :comment_count, :is_favorited, :own_vote
end
